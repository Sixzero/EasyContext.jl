using UUIDs
import PromptingTools: aigenerate
using HTTP: RequestError
using OpenRouter: Tool

export FluidAgent, work, create_FluidAgent, to_native_tools

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
    extractor_type  # Required - provide NativeCallExtractor or other AbstractExtractor implementation
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

"""Convert a single tool entry to OpenRouter.Tool(s). Returns vector (tool groups yield multiple).
Override in downstream packages for tool groups, MCP tools, etc."""
to_native_tools(tool) = to_native_tools_from_schema(get_tool_schema(tool))
to_native_tools_from_schema(::Nothing) = Tool[]
to_native_tools_from_schema(schema::ToolSchema) = [to_openrouter_tool(schema)]
to_native_tools_from_schema(nt::NamedTuple) = [to_openrouter_tool(nt)]

"""Convert agent's tools to OpenRouter.Tool vector for native API tool calling."""
function get_native_tools(agent::FluidAgent)
    tools = Tool[]
    for tool in agent.tools
        append!(tools, to_native_tools(tool))
    end
    tools
end
"""
Apply thinking API parameters for Claude models
"""
function apply_thinking_kwargs(api_kwargs::NamedTuple, model::String, thinking::Union{Nothing,Int}=nothing)
    # Only apply thinking for Claude models
    if !startswith(model, "claude") || thinking === nothing
        return api_kwargs
    end
    
    # Add thinking configuration
    thinking_config = (; type = "enabled", budget_tokens = thinking)
    
    # When thinking is enabled:
    # 1. Add thinking configuration
    # 2. Remove temperature and top_p as they're not allowed with thinking
    # max_tokens is left unset: OpenRouter.jl defaults it to the model's catalog
    # max output (>= thinking budget for all current Claude models).
    filtered_kwargs = NamedTuple(
        k => v for (k, v) in pairs(api_kwargs) if k != :temperature && k != :top_p
    )
    
    merge(filtered_kwargs, (; thinking = thinking_config))
end
# collect_execution_results(tasks) is defined in transform/source_format.jl
# collect_execution_results(extractor) is overloaded per extractor type (e.g. CallExtractor)

"""
Save partial AI content on interrupt. Appends [interrupted] marker.
If no AI content generated, appends [interrupted] to last user message.
"""
function save_interrupted_content!(session::Session, extractor::Union{AbstractExtractor, Nothing})
    partial_content = isnothing(extractor) || !hasproperty(extractor, :full_content) ? "" : extractor.full_content
    if !isempty(strip(partial_content))
        push_message!(session, create_AI_message(partial_content * "\n[interrupted]"))
    elseif !isempty(session.messages) && session.messages[end].role == :user
        session.messages[end].content *= " [interrupted]"
    end
end

"""Persist a native tool turn only after every tool result was collected."""
function commit_native_tool_turn!(collect_results::Function, session::Session, ai_msg::Message)
    tool_msgs = collect_results()
    push_message!(session, ai_msg)
    for tm in tool_msgs
        push_message!(session, tm)
    end
    tool_msgs
end

function work(agent::FluidAgent, session::AbstractString; kwargs...)
    conv_ctx = Session(; messages=[create_user_message(session)])
    work(agent, conv_ctx; kwargs...)
end
"""
Run an LLM interaction with tool execution.
"""
function work(agent::FluidAgent, session::Session; cache=nothing,
    quiet::Bool=false,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    on_error=noop,
    on_done=noop,
    on_finish=noop,
    on_start=noop,
    on_status=noop,  # Called with status: "COMPACTING" during compaction, "WORKING" after
    on_drain_user_queue=noop,  # Called before each LLM call; pushes queued user messages directly into session. Returns true if messages were drained.
    on_admitted=noop,  # Called right before each LLM request dispatch, after all setup (sys-msg, tools, compaction, payload). Used to release a bounded-admission slot; must be idempotent.
    on_queue_empty=Returns(true),  # Called after no-tool-call response; returns true if queue is empty (break), false if messages pending (continue loop).
    on_meta_ai=noop,  # Called with (tokens, cost, elapsed) after each LLM response
    io=stdout,
    tool_kwargs=Dict(),
    thinking::Union{Nothing,Int}=nothing,
    MAX_ITERATIONS=500,
    cutter::Union{AbstractCutter, Nothing}=nothing,  # Optional cutter for mid-session compaction
    on_retry=nothing,  # Called with (attempt, max_retries, sleep_time, error_msg) on transient LLM errors
    rethrow_on_interrupt::Bool=true,  # If false, return partial content instead of rethrowing on interrupt
    tool_choice::String="auto",  # "none" forbids tool calls but INVALIDATES the message-level prompt cache (Anthropic docs: "changes to tool_choice ... affect message blocks"). For cache-riding throwaway inferences keep "auto" and set drop_tool_calls=true instead.
    drop_tool_calls::Bool=false,  # Discard returned tool_calls unexecuted (dropped from session; response object untouched). Unlike tool_choice="none", does NOT alter the outbound request — for read-only inferences that must preserve the cached prefix.
    )
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
    completed = false  # Distinguish natural completion from iteration-limit exhaustion

    try
        while i < MAX_ITERATIONS
            i += 1

            # Drain any queued user messages before LLM call
            on_drain_user_queue()

            # Re-initialize the system message after drain: a drain may invalidate it
            # (content = "") when settings/devices changed (e.g. rotated CDP token).
            # No-op when content is already built.
            sys_msg_content = initialize!(agent.sys_msg, agent)

            # Recompute native tools after drain (tools may be populated/updated by drain)
            native_tools = get_native_tools(agent)

            # Check if compaction is needed before LLM call
            if cutter !== nothing && should_cut(cutter, session)
                on_status("COMPACTING")
                do_cut!(cutter, session)
                on_status("WORKING")
            end

            pt_messages = to_PT_messages(session, sys_msg_content)

            # ── Shared: extractor, streaming callback, LLM call ──
            extractor = agent.extractor_type(agent.tools)
            extractor_fn(text) = extract_tool_calls(text, extractor, io; kwargs=tool_kwargs)

            cb = create(StreamCallbackTYPE(;
                io, on_start, on_error, highlight_enabled, process_enabled, quiet,
                on_meta_ai,
                on_done = () -> begin
                    process_enabled && extract_tool_calls("", extractor, io; kwargs=tool_kwargs, is_flush=true)
                    on_done()
                end,
                on_content = process_enabled ? extractor_fn : noop,
            ))
            # Setup for this iteration is done — the request that follows is I/O-bound.
            on_admitted()

            response = aigenerate_with_config(agent.model, pt_messages;
                cache, api_kwargs, streamcallback=cb, verbose=false, tools=native_tools, tool_choice, on_retry)

            # ── Post-response handling (native API tool calling) ──
            # Hard read-only boundary: with tool_choice="none" (provider might still return
            # tool_calls) or drop_tool_calls=true (cache-safe throwaway inference), NEVER
            # execute them. Drop them and treat the response as plain text.
            tool_calls = (tool_choice == "none" || drop_tool_calls) ? nothing : response.tool_calls
            ai_msg = create_AI_message(response.content; tool_calls)
            hasproperty(io, :message_id) && (ai_msg.id = io.message_id)

            # No tool calls → persist the assistant response immediately.
            if tool_calls === nothing || isempty(tool_calls)
                push_message!(session, ai_msg)
                if on_queue_empty()
                    completed = true
                    break
                else
                    # new assistant message is needed so we don't break
                end
            else
                process_native_tool_calls!(extractor, tool_calls, io; kwargs=tool_kwargs)

                # Approval continuations need the tool_use persisted before pausing.
                if any_tool_needs_approval(extractor)
                    push_message!(session, ai_msg)
                    completed = true
                    break
                end

                # Commit a native tool turn atomically. If collection is interrupted
                # or fails, the session must not retain tool_use entries without results.
                commit_native_tool_turn!(session, ai_msg) do
                    collect_tool_messages(extractor; io)
                end
            end

            # Next iteration's assistant message ID
            hasproperty(io, :message_id) && (io.message_id = string(uuid4()))
        end
        if i >= MAX_ITERATIONS && !completed
            @warn "Agent reached maximum unsupervised iteration limit ($MAX_ITERATIONS). Contact dev@todofor.ai to increase."
            push_message!(session, create_user_message_with_vectors("[SYSTEM] Agent reached the maximum number of unsupervised iterations ($MAX_ITERATIONS). Send a new message to continue the conversation. If you need a higher autonomous limit, please contact dev@todofor.ai"))
        end
    catch e
        if is_interrupt(e)
            @info "Interrupt caught in work()" exception_type=typeof(e) has_extractor=!isnothing(extractor)
            # Close any open streaming block: the aborted stream never fires on_done,
            # so without this the frontend keeps a dangling "Thinking"/streaming block
            # (generationCompleted stays false, persisted in the DB too).
            if process_enabled && !isnothing(extractor)
                try
                    extract_tool_calls("", extractor, io; kwargs=tool_kwargs, is_flush=true)
                catch flush_err
                    @warn "Failed to flush open block on interrupt" exception=flush_err
                end
            end
            save_interrupted_content!(session, extractor)
            on_finish()
            if rethrow_on_interrupt
                rethrow(e)
            else
                partial = isnothing(extractor) || !hasproperty(extractor, :full_content) ? "" : extractor.full_content
                return isempty(strip(partial)) ? response : (content=partial * "\n[interrupted]", tool_calls=nothing)
            end
        else
            rethrow(e)
        end
    end

    on_finish()

    return response
end
