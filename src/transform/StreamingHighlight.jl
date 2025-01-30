
using StreamCallbacksExt
using StreamCallbacksExt: format_ai_message, format_user_message

export StreamCallbackConfig, create
include("syntax_highlight.jl")

@kwdef struct StreamCallbackConfig
    io::IO=stdout
    on_error = noop
    on_done = noop
    on_start = noop
    on_content = nothing
    highlight_enabled::Bool = true
    process_enabled::Bool = true
end

create(config::StreamCallbackConfig) = begin
    state = SyntaxHighlightState(io=config.io)
    
    content_handler = if config.process_enabled && config.highlight_enabled
        text -> (handle_text(state, text); !isnothing(config.on_content) && config.on_content(text))
    elseif config.process_enabled 
        text -> config.on_content(text)
    elseif config.highlight_enabled
        text -> handle_text(state, text)
    else
        text -> text
    end

    StreamCallbackChannelWrapper(;
        callback = StreamCallbackWithHooks(
            content_formatter = content_handler,
            on_meta_usr = (tokens, cost, elapsed) -> (flush_state(state); format_user_message(tokens, cost, elapsed)),
            on_meta_ai = (tokens, cost, elapsed) -> (flush_state(state); format_ai_message(tokens, cost, elapsed)), 
            on_error = e -> e isa InterruptException ? rethrow(e) : config.on_error(e),
            on_done = () -> (flush_state(state); config.on_done()),
            on_stop_sequence = stop_sequence -> handle_text(state, stop_sequence),
            on_start = config.on_start
        )
    )
end

flush_state(state) = (write(state.buffer, state.current_line); state.current_line = ""; process_buffer(state, flushh=true))
