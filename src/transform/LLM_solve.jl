include("syntax_highlight.jl")

function LLM_solve(conv, cache; model::String="claude-3-5-sonnet-20241022", stop_sequences=[], on_meta_usr=noop, on_text=noop, on_meta_ai=noop, on_error=noop, on_done=noop, on_start=noop, top_p=0.8)
    # display([(m.role, m.content) for m in conv.messages])
    channel = ai_stream(conv; model, cache, top_p, printout=false, stop_sequences)
    highlight_state = SyntaxHighlightState()
    
    try
        process_stream(channel; 
                on_text     = text -> (handle_text(highlight_state, text); on_text(text)),
                on_meta_usr = meta -> (flush_highlight(highlight_state); on_meta_usr(meta); print_user_message(meta)),
                on_meta_ai  = (meta, full_msg) -> (handle_text(highlight_state, meta["stop_sequence"]); flush_highlight(highlight_state); on_meta_ai(create_AI_message(full_msg, meta)); print_ai_message(meta)),
                on_error,
                on_done     = () -> (flush_highlight(highlight_state); on_text("\n"); on_done()), # add a newline to mark the last line to be closed and is processable
                on_start)
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        return e
    end
end

# Helper functions
flush_highlight(state) = (write(state.buffer, state.current_line); (state.current_line = "";); process_buffer(state, flush=true))
print_user_message(meta) = println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))\n\e[36m¬ \e[0m")
print_ai_message(meta) = println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")

