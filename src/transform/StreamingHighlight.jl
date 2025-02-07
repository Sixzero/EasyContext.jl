
using StreamCallbacksExt
using StreamCallbacksExt: format_ai_meta, format_user_meta
using StreamCallbacksExt: dict_user_meta, dict_ai_meta

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
    StreamCallbackWithHooks(
            content_formatter = content_handler,
            on_meta_usr       = (tokens, cost, elapsed) -> (flush_state(state); format_user_meta(tokens, cost, elapsed)),
            on_meta_ai        = (tokens, cost, elapsed) -> (flush_state(state); format_ai_meta(tokens, cost, elapsed)), 
            on_start          = config.on_start,
            on_done           = () -> (flush_state(state); config.on_done()),
            on_error          = e -> ((e isa InterruptException ? rethrow(e) : (println(config.io, err_msg); config.on_error(e)))),
            on_stop_sequence  = stop_sequence -> handle_text(state, stop_sequence),
        )
    # )
end
pickStreamCallbackforIO(io::IOBuffer) = StreamCallbackConfig
pickStreamCallbackforIO(io::IO)       = StreamCallbackConfig

@kwdef struct SocketStreamCallbackConfig
    io::IO=stdout
    on_error::Function = noop
    on_done::Function = noop
    on_start::Function = noop
    on_content::Function = noop
    highlight_enabled::Bool = false
    process_enabled::Bool = false
    mode::String = "normal"
end
create(config::SocketStreamCallbackConfig) = begin
    StreamCallbackWithHooks(
        content_formatter = text_chunk -> write(config.io, text_chunk),
        on_meta_usr       = (tokens, cost, elapsed) -> (write(config.io, dict_user_meta(tokens, cost, elapsed))),
        on_meta_ai        = (tokens, cost, elapsed) -> (write(config.io, dict_ai_meta(tokens, cost, elapsed))), 
        on_start          = ()            -> (write(config.io, Dict("event" => "start", "mode" => config.mode)); config.on_start()),
        on_done           = ()            -> (write(config.io, Dict("event" => "done", "mode" => config.mode))),
        on_error          = e             -> e isa InterruptException ? rethrow(e) : (write(config.io, Dict("event" => "error", "error" => e));config.on_error(e)),
        on_stop_sequence  = stop_sequence -> write(config.io, Dict("event" => "stop_sequence", "stop_sequence" => stop_sequence)),
    )
end

flush_state(state) = (write(state.buffer, state.current_line); state.current_line = ""; process_buffer(state, flushh=true))
