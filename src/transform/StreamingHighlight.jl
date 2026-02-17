
using OpenRouter
using OpenRouter: format_ai_meta, format_user_meta

export StreamCallbackConfig, create
include("syntax_highlight.jl")

@kwdef struct StreamCallbackConfig
    io::IO=stdout
    on_error::Function   = noop
    on_done::Function = noop
    on_start::Function = noop
    on_content::Function = noop
    highlight_enabled::Bool = true
    process_enabled::Bool = true
    quiet::Bool = false
    mode::String = "normal"
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

    # StreamCallbackChannelWrapper(;
        # callback = 
    HttpStreamHooks(
            content_formatter = content_handler,
            on_meta_usr       = config.quiet ? (tokens, cost, elapsed) -> nothing : (tokens, cost, elapsed) -> (flush_state(state); format_user_meta(tokens, cost, elapsed)),
            on_meta_ai        = config.quiet ? (tokens, cost, elapsed) -> nothing : (tokens, cost, elapsed) -> (flush_state(state); format_ai_meta(tokens, cost, elapsed)),
            on_start          = config.on_start,
            on_done           = () -> (flush_state(state); config.on_done()),
            on_error          = e -> ((e isa InterruptException ? rethrow(e) : (println(config.io, e); config.on_error(e)))),
            on_stop_sequence  = stop_sequence -> handle_text(state, stop_sequence),
            throw_on_error = true
        )
    # )
end

"""
This is a function just to allow users of the library to pick the correct StreamCallbackConfig for their IO type.
"""
pickStreamCallbackforIO(io::IO)       = StreamCallbackConfig


flush_state(state) = (write(state.buffer, state.current_line); state.current_line = ""; process_buffer(state, flushh=true))
