using UUIDs
using PromptingTools
using PromptingTools: aigenerate
using StreamCallbacksExt: needs_tool_execution

export FluidAgent, execute_tools, work, create_FluidAgent

abstract type AbstractAgent end

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent{S<:AbstractSysMessage} <: AbstractAgent
    tools::Vector
    model::Union{String,ModelConfig} = "claude"
    workspace::String = pwd()
    extractor_type=ToolTagExtractor
    sys_msg::S=SysMessageV1()
end 

# create_FluidAgent to prevent conflict with the constructor
function create_FluidAgent(model::Union{String, ModelConfig}="claude"; sys_msg::String="You are a helpful assistant.", tools::Vector, extractor_type=ToolTagExtractor, custom_system_message::Union{String, Nothing}=nothing)
    sys_msg_v2 = SysMessageV2(; sys_msg, custom_system_message)
    agent = FluidAgent(; tools, model, extractor_type, sys_msg=sys_msg_v2)
    agent
end

get_tool_descriptions(agent::FluidAgent) = get_tool_descriptions(agent.tools)
"""
Get tool descriptions for system prompt
"""
function get_tool_descriptions(tools::AbstractVector)
    descriptions = get_description.(tools)
    """
    # Available tools:
    $(join(descriptions, "\n\n"))"""
end

"""
Execute a single tool
"""
function execute_tool!(agent::FluidAgent, tool::AbstractTool; no_confirm=false)
    result = execute(tool; no_confirm)
    result
end

"""
Get formatted tool results for LLM context
"""
function get_tool_context(agent::FluidAgent)
    isempty(agent.tool_results) && return ""
    
    output = "Previous tool results:\n"
    for (id, result) in agent.tool_results
        output *= "- $result\n"
    end
    output
end

"""
Generate system prompt for LLM
"""
function get_system_prompt(agent::FluidAgent)
    """
    You are an AI assistant that can use tools to help accomplish tasks.
    
    $(get_tool_descriptions(agent))
    
    Always format tool calls exactly as shown in the examples.
    Wait for tool results before proceeding with dependent steps.
    """
end

"""
Apply thinking API parameters for Claude models
"""
function apply_thinking_kwargs(api_kwargs::NamedTuple, model::String, thinking::Union{Nothing,Int}=nothing)
    # Only apply thinking for Claude models
    if !startswith(model, "claude") || thinking === nothing
        return api_kwargs
    end
    
    # Set max_tokens to 16000 + thinking budget
    max_tokens = 16000 + thinking
    
    # Add thinking configuration
    thinking_config = (; type = "enabled", budget_tokens = thinking)
    
    # When thinking is enabled, we need to:
    # 1. Add thinking configuration
    # 2. Set max_tokens appropriately
    # 3. Remove temperature and top_p as they're not allowed with thinking
    
    # Start with a clean kwargs without temperature and top_p
    filtered_kwargs = NamedTuple(
        k => v for (k, v) in pairs(api_kwargs) if k != :temperature && k != :top_p
    )
    
    # Merge with thinking config and max_tokens
    merge(filtered_kwargs, (; 
        thinking = thinking_config, 
        max_tokens = max_tokens
    ))
end

function get_tool_results_agent(tool_tasks)
    tasks = fetch.(values(tool_tasks))
    str_results = join(result2string.(tasks), "\n")
    img_results = String[]
    for img_vec in resultimg2base64.(tasks)
        !isnothing(img_vec) && append!(img_results, img_vec)
    end
    audio_results = String[]
    for audio_vec in resultaudio2base64.(tasks)
        !isnothing(audio_vec) && append!(audio_results, audio_vec)
    end
    (str_results, img_results, audio_results)
end

"""
Check if response content contains any stop sequences, indicating tool execution is needed.
This is a fallback for models that don't properly support stop sequences.
"""
function content_has_stop_sequences(content::AbstractString, stop_sequences::Vector{String})
    isempty(stop_sequences) && return false
    any(seq -> occursin(seq, content), stop_sequences)
end

function work(agent::FluidAgent, conv::AbstractString; kwargs...)
    conv_ctx = Session(; messages=[create_user_message(conv)])
    work(agent, conv_ctx; kwargs...)
end
"""
Run an LLM interaction with tool execution.
"""
function work(agent::FluidAgent, conv; cache=nothing,
    no_confirm=false,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    on_error=noop,
    on_done=noop,
    on_finish=noop,
    on_start=noop,
    io=stdout,
    tool_kwargs=Dict(),
    thinking::Union{Nothing,Int}=nothing,
    MAX_NUMBER_OF_TOOL_CALLS=6,
    )
    # Initialize the system message if it hasn't been initialized yet
    sys_msg_content = initialize!(agent.sys_msg, agent)
    
    # Collect unique stop sequences from tools
    stop_sequences = unique(String[stop_sequence(tool) for tool in agent.tools if has_stop_sequence(tool)])
    length(stop_sequences) > 1 && @warn "Untested: Multiple different stop sequences detected: $(join(stop_sequences, ", "))"
    
    model_name = get_model_name(agent.model)
    
    # Base API kwargs - now using centralized logic
    base_kwargs = (; top_p=0.7, temperature=0.5)
    api_kwargs = get_api_kwargs_for_model(model_name, base_kwargs)
    
    # Apply thinking and stop sequences using centralized functions
    api_kwargs = apply_thinking_kwargs(api_kwargs, model_name, thinking)
    api_kwargs = apply_stop_sequences(model_name, api_kwargs, stop_sequences)
    
    StreamCallbackTYPE = pickStreamCallbackforIO(io)
    response = nothing
    
    for i in 1:MAX_NUMBER_OF_TOOL_CALLS
        # Create new ToolTagExtractor for each run
        extractor = agent.extractor_type(agent.tools)

        cb = create(StreamCallbackTYPE(; 
            io, on_start, on_error, highlight_enabled, process_enabled,
            on_done = () -> begin
                process_enabled && extract_tool_calls("\n", extractor, io; kwargs=tool_kwargs, is_flush=true)
                on_done()
            end,
            on_content = process_enabled ? (text -> extract_tool_calls(text, extractor, io; kwargs=tool_kwargs)) : noop,
        ))
        model = agent.model
        @save "conv.jld2" conv sys_msg_content model api_kwargs cache
        
        response = aigenerate_with_config(agent.model, to_PT_messages(conv, sys_msg_content);
            cache, api_kwargs, streamcallback=cb, verbose=false)
        
        push_message!(conv, create_AI_message(response.content))
        execute_tools(extractor; no_confirm)

        are_there_simple_tools = filter(tool -> execute_required_tools(tool), fetch.(values(extractor.tool_tasks))) # TODO... we have eecute_tools and this too??? WTF???
        
        # Check if tool execution is needed - either from callback or content contains stop sequences
        needs_execution = needs_tool_execution(cb.run_info) || content_has_stop_sequences(response.content, stop_sequences)
        
        (!needs_execution && isempty(are_there_simple_tools)) && break
        are_tools_cancelled(extractor) && (@info "All tools were cancelled by user, stopping further processing"; break)

        tools = [(id, fetch(tool)) for (id, tool) in extractor.tool_tasks]

        # Add tool results to conversation for next iteration
        result_str, result_img, result_audio = get_tool_results_agent(extractor.tool_tasks)
        
        prev_assistant_msg_id = conv.messages[end].id
        tool_results_usr_msg = create_user_message_with_vectors(result_str; images_base64=result_img, audio_base64=result_audio)

        push_message!(conv, tool_results_usr_msg)
        
        if !isa(io, Base.TTY)
            write(io, create_user_message("Tool results."))
            for (id, tool) in tools
                write(io, tool, id, prev_assistant_msg_id)
            end
        end
    end

    on_finish()

    return response
end
