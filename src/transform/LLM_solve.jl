include("syntax_highlight.jl")
using StreamCallbacksExt
using StreamCallbacksExt: format_ai_message, format_user_message

function LLM_solve(conv, cache;
    extractor,
    root_path,
    stop_sequences=[],
    model::String="claude",
    on_text=noop,
    on_error=noop,
    on_done=noop,
    on_start=noop,
    top_p=0.8,)

    reset!(extractor)
    highlight_state = SyntaxHighlightState()

    # Create callback with hooks
    cb = StreamCallbackWithHooks(
        content_formatter = text -> begin
            handle_text(highlight_state, text)
            on_text(text)
            extract_commands(text, extractor, root_path=root_path)
        end,
        on_meta_usr = (tokens, cost, elapsed) -> begin
            flush_highlight(highlight_state)
            format_user_message(tokens, cost, elapsed)
        end,
        on_meta_ai = (tokens, cost, elapsed) -> begin
            flush_highlight(highlight_state)
            format_ai_message(tokens, cost, elapsed)
        end,
        on_error = e -> begin
            on_error(e)
            e isa InterruptException && rethrow(e)
            @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        end,
        on_done = () -> begin
            flush_highlight(highlight_state)
            extract_commands("\n", extractor, root_path=root_path)
            on_done()
        end,
        on_stop_sequence = (stop_sequence) -> handle_text(highlight_state, stop_sequence),
        on_start = on_start,
    )

    try
        msg = aigenerate(to_PT_messages(conv);
            model, cache, streamcallback=cb, api_kwargs=(; stop_sequences=stop_sequences, top_p=top_p, max_tokens=8192), verbose=false,)
        update_last_user_message_meta(conv, cb)
        !isnothing(cb.run_info.stop_sequence) && !isempty(cb.run_info.stop_sequence) && (msg.content *= cb.run_info.stop_sequence)
        conv(msg)
        return msg, cb
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        # Create AIMessage with error and partial response
        error_msg = AIMessage(
            "Error: $(sprint(showerror, e))\n\nPartial response: $(extractor.full_content)",
            Dict("error" => e, "partial_response" => extractor.full_content)
        )
        return error_msg, cb
    end
end

# Helper functions
flush_highlight(state) = (write(state.buffer, state.current_line); (state.current_line = "";); process_buffer(state, flush=true))
print_user_message(meta) = println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))\n\e[36m¬ \e[0m")
print_ai_message(meta) = println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")

