using UUIDs
using PromptingTools
using PromptingTools: aigenerate
using StreamCallbacksExt: needs_tool_execution

export FluidAgent, execute_tools, work, create_FluidAgent

abstract type AbstractAgent end

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent{E<:AbstractExtractor, S<:AbstractSysMessage} <: AbstractAgent
    tools::Vector
    model::String = "claude"
    workspace::String = pwd()
    extractor::E=ToolTagExtractor(; tools)
    sys_msg::S=SysMessageV1()
end 

# create_FluidAgent to prevent conflict with the constructor
function create_FluidAgent(model::String="claude"; sys_msg::String="You are a helpful assistant.", tools::Vector, extractor_type=ToolTagExtractor)
    extractor = extractor_type(tools)
    sys_msg_v1 = SysMessageV1(; sys_msg)
    agent = FluidAgent(; tools, model, extractor, sys_msg=sys_msg_v1)
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
    join(result2string.(fetch.(values(tool_tasks))), "\n")
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
    on_start=noop,
    io=stdout,
    tool_kwargs=Dict(),
    thinking::Union{Nothing,Int}=nothing
    )
    # Initialize the system message if it hasn't been initialized yet
    sys_msg_content = initialize!(agent.sys_msg, agent)
    
    # Collect unique stop sequences from tools only if IO is stdout
    stop_sequences = unique(String[stop_sequence(tool) for tool in agent.tools if has_stop_sequence(tool)])
    
    if length(stop_sequences) > 1
        @warn "Untested: Multiple different stop sequences detected: $(join(stop_sequences, ", "))"
    end
    
    # Base API kwargs without stop sequences
    api_kwargs = (; top_p=0.7, temperature=0.5, )
    
    if startswith(agent.model, "claude") # NOTE: o3m does not support temperature and top_p
        api_kwargs = (; api_kwargs..., max_tokens=16384)
    end
    
    if agent.model == "o3m" # NOTE: o3m does not support temperature and top_p
        api_kwargs = (; )
    end

    # Apply thinking API parameters if specified
    api_kwargs = apply_thinking_kwargs(api_kwargs, agent.model, thinking)
    
    # Apply stop sequences
    api_kwargs = apply_stop_seq_kwargs(api_kwargs, agent.model, stop_sequences)
    StreamCallbackTYPE = pickStreamCallbackforIO(io)

    response = nothing
    while true
        # Create new ToolTagExtractor for each run
        extractor = typeof(agent.extractor)(agent.tools)
        agent.extractor = extractor

        cb = create(StreamCallbackTYPE(; io, on_start, on_error, highlight_enabled, process_enabled,
            on_done = () -> begin
                process_enabled && extract_tool_calls("\n", extractor, io; kwargs=tool_kwargs, is_flush=true)
                on_done()
            end,
            on_content = process_enabled ? (text -> extract_tool_calls(text, extractor, io; kwargs=tool_kwargs)) : noop,
        ))

        response = aigenerate(
            to_PT_messages(conv, sys_msg_content);
            model=agent.model,
            cache, 
            api_kwargs,
            streamcallback=cb,
            verbose=false
        )
        
        push_message!(conv, create_AI_message(response.content))

        execute_tools(extractor; no_confirm)
        # idea:
        # res::TextResult = execute_tool(browser_use_tool(arguments))
        # res::ImgNTextResult = execute_tool(click_brower_use(arguments))
        # res::ImgNTextResult = execute_tool(browser_use_tool(arguments))
        # res::VoiceResult = execute_tool(generate_voice(arguments))

        are_there_simple_tools = filter(tool -> execute_required_tools(tool), fetch.(values(agent.extractor.tool_tasks))) # TODO... we have eecute_tools and this too??? WTF???
        # Break if no more tool execution needed
        !needs_tool_execution(cb.run_info) && isempty(are_there_simple_tools) && break
        
        # Check if all tools were cancelled
        if are_tools_cancelled(extractor)
            @info "All tools were cancelled by user, stopping further processing"
            break
        end

        tools = [(id, fetch(tool)) for (id, tool) in agent.extractor.tool_tasks]

        # Add tool results to conversation for next iteration
        result = get_tool_results_agent(agent.extractor.tool_tasks)
        
        tool_results_usr_msg = create_user_message(result)
        push_message!(conv, tool_results_usr_msg)
        
        prev_assistant_msg_id = conv.messages[end].id
        !isa(io, Base.TTY) && write(io, create_user_message("Tool results."))
        for (id, tool) in tools
            !isa(io, Base.TTY) && write(io, tool, id, prev_assistant_msg_id)
        end
        
    end

    return response
end

"""
Apply stop sequence kwargs based on model type and available sequences.
"""
function apply_stop_seq_kwargs(api_kwargs::NamedTuple, model::String, stop_sequences::Vector{String})
    isempty(stop_sequences) && return api_kwargs
    startswith(model, "gem") && return api_kwargs
    key = startswith(model, "claude") ? :stop_sequences : :stop
    merge(api_kwargs, (; key => stop_sequences))
end