using StreamCallbacksExt

function LLM_solve(conv, cache;
    extractor,
    stop_sequences=[],
    model::String="claude",
    on_text=noop,
    on_error=noop,
    on_done=noop,
    on_start=noop,
    top_p=0.8,
    image=nothing,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    tool_kwargs=Dict())

    reset!(extractor)
    
    cb = create(StreamCallbackConfig(
        on_text = on_text,
        on_error = on_error,
        on_start = on_start,
        on_done = () -> begin
            process_enabled && extract_tool_calls("\n", extractor; kwargs=tool_kwargs, is_flush=true)
            on_done()
        end,
        content_processor = text -> process_enabled ? extract_tool_calls(text, extractor; kwargs=tool_kwargs) : nothing,
        highlight_enabled = highlight_enabled,
        process_enabled = process_enabled
    ))
    
    try
        msg = aigenerate(to_PT_messages(conv); 
            model, cache, streamcallback=cb, api_kwargs=(; stop_sequences, top_p=top_p, max_tokens=8192), verbose=false,)
        update_last_user_message_meta(conv, cb)
        stopsig = !isnothing(cb.run_info.stop_sequence) && !isempty(cb.run_info.stop_sequence) ? cb.run_info.stop_sequence : ""
        conv(msg, stopsig)
        return msg, cb
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        error_msg = AIMessage("Error: $(sprint(showerror, e))\n\nPartial response: $(extractor.full_content)")
        return error_msg, cb
    end
end
