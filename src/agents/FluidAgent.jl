using UUIDs
import PromptingTools: aigenerate
using HTTP: RequestError

export FluidAgent, work, create_FluidAgent

# Check if exception is InterruptException (direct or wrapped in HTTP.RequestError)
is_interrupt(e::InterruptException) = true
is_interrupt(e::RequestError) = e.error isa InterruptException
is_interrupt(e) = false

abstract type AbstractAgent end

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent <: AbstractAgent
    tools::Vector
    model::Union{String,ModelConfig} = "claude"
    workspace::String = pwd()
    extractor_type  # Required - provide CallExtractor or other AbstractExtractor implementation
    sys_msg::AbstractSysMessage=SysMessageV1()
end

# create_FluidAgent to prevent conflict with the constructor
function create_FluidAgent(model::Union{String, ModelConfig}="claude"; sys_msg::String="You are a helpful assistant.", tools::Vector, extractor_type, custom_system_message::Union{String, Nothing}=nothing)
    sys_msg_v2 = SysMessageV2(; sys_msg, custom_system_message)
    agent = FluidAgent(; tools, model, extractor_type, sys_msg=sys_msg_v2)
    agent
end

# New function that directly accepts a system message object
function create_FluidAgent_with_sysmsg(model::Union{String, ModelConfig}, sysmsg::AbstractSysMessage; tools::Vector, extractor_type)
    agent = FluidAgent(; tools, model, extractor_type, sys_msg=sysmsg)
    agent
end

get_tool_descriptions(agent::FluidAgent) = get_tool_descriptions(agent.tools)
"""
Get tool descriptions for system prompt.
"""
function get_tool_descriptions(tools::AbstractVector)
    descriptions = get_description.(tools)
    """
# Available tools:
$(join(descriptions, "\n"))"""
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
# collect_execution_results(tasks) is defined in transform/source_format.jl
# collect_execution_results(extractor) is overloaded per extractor type (e.g. CallExtractor)

"""
Save partial AI content on interrupt. Appends [interrupted] marker.
If no AI content generated, appends [interrupted] to last user message.
"""
function save_interrupted_content!(session::Session, extractor::Union{AbstractExtractor, Nothing})
    partial_content = isnothing(extractor) ? "" : extractor.full_content
    if !isempty(strip(partial_content))
        push_message!(session, create_AI_message(partial_content * "\n[interrupted]"))
    elseif !isempty(session.messages) && session.messages[end].role == :user
        session.messages[end].content *= " [interrupted]"
    end
end

function work(agent::FluidAgent, session::AbstractString; kwargs...)
    conv_ctx = Session(; messages=[create_user_message(session)])
    work(agent, conv_ctx; kwargs...)
end
"""
Run an LLM interaction with tool execution.
"""
function work(agent::FluidAgent, session::Session; cache=nothing,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    on_error=noop,
    on_done=noop,
    on_finish=noop,
    on_start=noop,
    on_status=noop,  # Called with status: "COMPACTING" during compaction, "WORKING" after
    on_tool_results=noop,  # Called with (result_str, result_img, result_audio) after tool execution
    io=stdout,
    tool_kwargs=Dict(),
    thinking::Union{Nothing,Int}=nothing,
    MAX_ITERATIONS=500,
    cutter::Union{AbstractCutter, Nothing}=nothing,  # Optional cutter for mid-session compaction
    source_tracker::Union{SourceTracker, Nothing}=nothing,  # Required if cutter is provided
    )
    # Initialize the system message if it hasn't been initialized yet
    sys_msg_content = initialize!(agent.sys_msg, agent)

    model_name = get_model_name(agent.model)

    # Base API kwargs - now using centralized logic
    base_kwargs = (; top_p=0.7)
    api_kwargs = get_api_kwargs_for_model(agent.model, base_kwargs)

    # Apply thinking kwargs
    api_kwargs = apply_thinking_kwargs(api_kwargs, model_name, thinking)

    StreamCallbackTYPE = pickStreamCallbackforIO(io)
    response = nothing
    extractor = nothing  # Declare here so it's accessible in catch block
    i = 0

    try
        while i < MAX_ITERATIONS
            i += 1

            # Create new extractor for each run
            extractor = agent.extractor_type(agent.tools)
            extractor_fn(text) = begin
                extract_tool_calls(text, extractor, io; kwargs=tool_kwargs)
            end

            cb = create(StreamCallbackTYPE(;
                io, on_start, on_error, highlight_enabled, process_enabled,
                on_done = () -> begin
                    process_enabled && extract_tool_calls("\n", extractor, io; kwargs=tool_kwargs, is_flush=true)
                    on_done()
                end,
                on_content = process_enabled ? extractor_fn : noop,
            ))
            model = agent.model
            # @save "conv.jld2" conv sys_msg_content model api_kwargs cache

            # Check if compaction is needed before LLM call
            if cutter !== nothing && source_tracker !== nothing && should_cut(cutter, session, source_tracker)
                on_status("COMPACTING")
                do_cut!(cutter, session, source_tracker)
                on_status("WORKING")
            end

            pt_messages = to_PT_messages(session, sys_msg_content)
            response = aigenerate_with_config(agent.model, pt_messages;
                cache, api_kwargs, streamcallback=cb, verbose=false)

            push_message!(session, create_AI_message(response.content))



            
            # Tools already executed during streaming (emit_tool_callback). Check if we should continue.
            are_tools_cancelled(extractor) && break
            
            # Wait for running tool tasks and collect results
            result_str, result_img, result_audio = collect_execution_results(extractor)
            if isempty(strip(result_str)) && isempty(result_img) && isempty(result_audio)
                result_str = "(tools finished execution)"
            end
            push_message!(session, create_user_message_with_vectors(result_str; images_base64=result_img, audio_base64=result_audio))
            on_tool_results(result_str, result_img, result_audio)

            # Next iteration's assistant message ID
            io.message_id = string(uuid4())
        end
        if i >= MAX_ITERATIONS
            @warn "Agent reached maximum unsupervised iteration limit ($MAX_ITERATIONS). Contact dev@todofor.ai to increase."
            push_message!(session, create_user_message_with_vectors("[SYSTEM] Agent reached the maximum number of unsupervised iterations ($MAX_ITERATIONS). Send a new message to continue the conversation. If you need a higher autonomous limit, please contact dev@todofor.ai"))
        end
    catch e
        if is_interrupt(e)
            @info "Interrupt caught in work()" exception_type=typeof(e) has_extractor=!isnothing(extractor)
            save_interrupted_content!(session, extractor)
            on_finish()
            rethrow(e)
        else
            rethrow(e)
        end
    end

    on_finish()

    return response
end
