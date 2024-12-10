include("syntax_highlight.jl")
using StreamCallbacksExt
using StreamCallbacksExt: format_ai_message, format_user_message

function LLM_solve(conv, cache;
    stop_sequences=[],
    model::String="claude",
    on_text=noop,
    on_error=noop,
    on_done=noop,
    on_start=noop,
    top_p=0.8,)

    highlight_state = SyntaxHighlightState()

    # Create callback with hooks
    cb = StreamCallbackWithHooks(
        content_formatter = text -> begin
            handle_text(highlight_state, text)
            on_text(text)
            nothing
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
            on_text("\n")
            on_done()
        end,
        on_stop_sequence = (stop_sequence) -> handle_text(highlight_state, stop_sequence),
        on_start = on_start,
    )

    try
        msg = aigenerate(to_PT_messages(conv);
            model, cache, streamcallback=cb, api_kwargs=(; stop_sequences=stop_sequences, top_p=top_p),
        verbose=false,)
        return msg, cb
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        # Create AIMessage with error and partial response
        error_msg = AIMessage(
            "Error: $(sprint(showerror, e))\n\nPartial response: (cb.full_response)",
            Dict("error" => e, "partial_response" => "cb.full_response")
        )
        return error_msg, cb
    end
end

# Helper functions
flush_highlight(state) = (write(state.buffer, state.current_line); (state.current_line = "";); process_buffer(state, flush=true))
print_user_message(meta) = println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))\n\e[36m¬ \e[0m")
print_ai_message(meta) = println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")

