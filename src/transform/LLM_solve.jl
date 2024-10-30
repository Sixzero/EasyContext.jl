include("syntax_highlight.jl")

function LLM_solve(conv, cache; model::String="claude-3-5-sonnet-20240620", on_meta_usr=noop, on_text=noop, on_meta_ai=noop, on_error=noop, on_done=noop, on_start=noop)
    channel = ai_stream(conv, model=model, printout=false, cache=cache)
    highlight_state = SyntaxHighlightState()

    try
        process_stream(channel; 
                on_text     = text -> (on_text(text); handle_text(highlight_state, text)),
                on_meta_usr = meta -> (flush_highlight(highlight_state); on_meta_usr(meta); print_user_message(meta)),
                on_meta_ai  = (meta, full_msg) -> (flush_highlight(highlight_state); on_meta_ai(create_AI_message(full_msg, meta)); print_ai_message(meta)),
                on_error,
                on_done     = () -> (flush_highlight(highlight_state); on_done()),
                on_start)
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        return e
    end
end

# Helper functions
flush_highlight(state) = process_buffer(state, flush=true)
print_user_message(meta) = println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))\n\e[36m¬ \e[0m")
print_ai_message(meta) = println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")

