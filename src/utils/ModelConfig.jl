export ModelConfig, aigenerate_with_config
using OpenRouter: extract_provider_from_model, ModelConfig, StreamIdleTimeoutError
import PromptingTools: AbstractPromptSchema, OpenAISchema, CerebrasOpenAISchema, MistralOpenAISchema,
    AnthropicSchema, GoogleSchema, GroqOpenAISchema

# Re-export ModelConfig from OpenRouter
# Base.@kwdef mutable struct ModelConfig
#     slug::String  # provider:author/modelid format
#     schema::Union{AbstractRequestSchema, Nothing} = nothing
#     kwargs::NamedTuple = NamedTuple()
# end

# Single responsibility: extract model name from either string or config
get_model_name(model::String) = model
get_model_name(config::ModelConfig) = config.slug

# Helper: provider slug from model name, with OpenRouter's fallback behaviour.
_get_provider(model_name::String) =
    extract_provider_from_model(replace(model_name, r"\([^)]+\)$" => ""))

# Model-specific logic centralized in ModelConfig (now purely provider-based)
is_openai_reasoning_model(model_name::String) =
    _get_provider(model_name) == "openai"

is_mistral_model(model_name::String) = _get_provider(model_name) == "mistral"

is_claude_model(model_name::String) = _get_provider(model_name) == "anthropic"

is_grok_model(model_name::String) = _get_provider(model_name) == "xai"

"""
    get_api_kwargs_for_model(model_name::String, base_api_kwargs)

Get model-specific API kwargs for string model names.
"""
function get_api_kwargs_for_model(model_name::String, base_api_kwargs::NamedTuple)
    # Start with base kwargs or default reasoning model behavior
    api_kwargs = is_openai_reasoning_model(model_name) ? NamedTuple() : base_api_kwargs
    
    # NOTE: no Claude max_tokens override here anymore — OpenRouter.jl defaults
    # Anthropic max_tokens to the model's catalog max output when unset.
    # Remove top_p for mistral models
    if is_mistral_model(model_name) && haskey(api_kwargs, :top_p)
        api_kwargs = NamedTuple(k => v for (k, v) in pairs(api_kwargs) if k != :top_p)
    end
    
    return api_kwargs
end

"""
    get_api_kwargs_for_model(config::ModelConfig, base_api_kwargs)

Get model-specific API kwargs, applying model-specific rules and merging with defaults.
"""
function get_api_kwargs_for_model(config::ModelConfig, base_api_kwargs::NamedTuple)
    # Merge config kwargs with base kwargs first
    merged_kwargs = merge(config.kwargs, base_api_kwargs)
    
    # Then apply model-specific rules using the string version
    return get_api_kwargs_for_model(config.slug, merged_kwargs)
end

"""
    aigenerate_with_config(model::Union{ModelConfig,String}, prompt; 
                          request_id::Union{String, Nothing} = nothing,
                          kwargs...)

Generate AI response using a ModelConfig with merged defaults, or a model name string.
Optionally uses APIKeyManager for key selection.
"""
# Transient errors worth retrying (provider hiccups, not client errors)
#
# CLIProxyAPI pool exhaustion is explicitly NON-transient: when every OAuth
# credential for a provider is cooling down it returns one of two shapes:
#   API Error (503): auth_unavailable: no auth available; last upstream error:
#   {"error":{"type":"usage_limit_reached","plan_type":"prolite","resets_at":...}}
#   (status 429); retry in 42h8m45s (providers=codex, model=gpt-5.6-sol(high))
#   API Error (429): {"error":{"code":"model_cooldown","message":"All credentials for
#   model gpt-5.6-sol(high) are cooling down","reset_time":"42h8m45s","reset_seconds":...}}
# and our own gateway's sanitized relay of either ("temporarily at capacity").
# The cooldown is hours long — the embedded "(503)"/"status 429" would otherwise
# match the transient patterns and make us retry 3x with seconds of backoff on
# EVERY request until the cooldown ends. Fail fast instead so the caller surfaces
# a clear error / falls back to another model. Callers lowercase the message.
_is_pool_exhausted_error(m::AbstractString) =
    occursin("auth_unavailable", m) || occursin("no auth available", m) ||
    occursin("usage_limit_reached", m) || occursin("model_cooldown", m) ||
    occursin("temporarily at capacity", m) ||
    occursin(r"all credentials for model\b.*\bare cooling down"s, m)

"""
Parse the cooldown from a pool-exhaustion error message — `retry in 42h8m45s`,
CLIProxyAPI's `"reset_seconds":151725` / `"reset_time":"42h8m45s"`, or our gateway's
`Retry after 151725s`. Returns whole seconds, or `nothing` when absent.
"""
function parse_retry_after_seconds(msg::AbstractString)::Union{Int,Nothing}
    s = match(r"\"reset_seconds\"\s*:\s*(\d+)"i, msg)
    s !== nothing && return parse(Int, s[1])
    a = match(r"retry after\s+(\d+)s"i, msg)
    a !== nothing && return parse(Int, a[1])
    m = match(r"(?:retry in|\"reset_time\"\s*:\s*\")\s*(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?"i, msg)
    (m === nothing || all(isnothing, m.captures)) && return nothing
    h, mi, sec = (c -> c === nothing ? 0.0 : parse(Float64, c)).(m.captures)
    ceil(Int, h * 3600 + mi * 60 + sec)
end

"Format seconds as a compact `2h5m` / `4m10s` / `45s` duration."
function format_duration(seconds::Int)
    h, rem = divrem(seconds, 3600)
    m, s = divrem(rem, 60)
    h > 0 ? "$(h)h$(m > 0 ? "$(m)m" : "")" :
    m > 0 ? "$(m)m$(s > 0 ? "$(s)s" : "")" : "$(s)s"
end

# Stream stall (StreamIdleTimeoutError): the upstream accepted the request, then
# went byte-silent until the first-chunk/idle window expired.
#
# PRE-first-chunk stalls (zero bytes received) are RETRYABLE: nothing was
# generated, so a resend is idempotent, and each retry opens a fresh TCP
# connection — which fixes the common causes (dead connection, gateway blip,
# LB routing to a bad node). Worst case is max_retries × first-chunk window
# (~30s each) of visibly-narrated waiting via on_retry, then a clear error;
# the model gets its short cooldown only after the FINAL failed attempt.
#
# MID-stream stalls (chunks already received) still fail fast: a retry would
# re-stream the whole turn after up to another full idle window (300s) of
# silence, and partial content already reached the user.
_is_stall_error(e::StreamIdleTimeoutError) = true
_is_stall_error(e) =
    (hasproperty(e, :error) && _is_stall_error(e.error)) ||  # HTTP.RequestError-style wrappers
    _is_stall_error(sprint(showerror, e))
_is_stall_error(msg::AbstractString) = occursin("stream stalled", lowercase(msg))

_is_transient_error(e) = _is_transient_error(sprint(showerror, e))
function _is_transient_error(msg::AbstractString)
    m = lowercase(msg)
    _is_pool_exhausted_error(m) && return false
    any(p -> occursin(p, m), (
        "empty_stream", "upstream stream closed", "stream ended unexpectedly",
        "bad gateway", "service unavailable", "overloaded", "internal server error",
        "internal_server_error", "internal_error", "server_error", "stream error",
        "status 500", "status 502", "status 503", "status 429", "status 529",
        "(500)", "(502)", "(503)", "(429)", "(529)",
        "rate_limit", "rate limit", "too many requests",
        "econnreset", "connection reset",
        "eoferror", "broken pipe", "connection refused", "connection closed",
        "timeout", "timed out",
    ))
end

const AIGEN_MAX_RETRIES = 3

function _aigen_with_retry(f::Function; max_retries=AIGEN_MAX_RETRIES, on_retry=nothing, streamcallback=nothing, model_name::String="")
    for attempt in 1:max_retries
        try
            # A stream callback accumulates chunks in-place across the whole
            # request. On a retry the previous (failed/partial) attempt's chunks
            # are still there and `build_response_body` would rebuild from ALL of
            # them — duplicating or corrupting tool_calls (e.g. the same question
            # asked twice). Reset it so each attempt starts from a clean slate.
            attempt > 1 && streamcallback !== nothing && empty!(streamcallback)
            return f()
        catch e
            e isa InterruptException && rethrow(e)
            # HTTP.RequestError wrapping InterruptException
            hasproperty(e, :error) && e.error isa InterruptException && rethrow(e)
            # Mid-stream stall: chunks already reached the user; fail fast
            # (see stall comment above). No cooldown — the stream was healthy.
            stall = _is_stall_error(e)
            stall && !(streamcallback === nothing || isempty(streamcallback)) && rethrow(e)
            if attempt < max_retries && (stall || _is_transient_error(e))
                sleep_time = 2^attempt
                err_msg = _extract_error_message(e)
                @warn "Transient LLM error (attempt $attempt/$max_retries), retrying in $(sleep_time)s" exception=(e, catch_backtrace())
                if !isnothing(on_retry)
                    try on_retry(attempt, max_retries, sleep_time, err_msg) catch ex
                        @warn "on_retry callback failed" exception=(ex, catch_backtrace())
                    end
                end
                sleep(sleep_time)
            else
                # Pool exhaustion (hours-long provider cooldown) fails fast — record
                # it globally so the user-facing error can include the recovery ETA
                # instead of retrying into the same wall.
                isempty(model_name) || maybe_mark_pool_exhausted!(model_name, e)
                # Stall that survived all retries: short cooldown for logs/ETA.
                stall && !isempty(model_name) && maybe_mark_stalled!(model_name, e)
                rethrow(e)
            end
        end
    end
end

"""Extract a short error message from an exception for notification display."""
function _extract_error_message(e)
    s = sprint(showerror, e)
    # HTTP.RequestError: actual message is in "Underlying error: ..."
    m = match(r"Underlying error:\s*\"?(.+?)\"?\s*$"m, s)
    !isnothing(m) && return strip(something(m.captures[1]), '"')
    # Look for "Message: ..." pattern (e.g. from streaming errors)
    m = match(r"Message:\s*(.+?)(?:,|$)"m, s)
    !isnothing(m) && return something(m.captures[1])
    # Fallback: first non-empty line that isn't just a type name
    for line in split(s, '\n')
        stripped = strip(line)
        !isempty(stripped) && !endswith(stripped, ':') && return length(stripped) > 120 ? stripped[1:120] * "…" : stripped
    end
    first_line = first(split(s, '\n'))
    length(first_line) > 120 ? first_line[1:120] * "…" : first_line
end

function aigenerate_with_config(config::ModelConfig, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               on_retry=nothing,
                               kwargs...)
    # Get API key from global manager
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(config, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end

    _aigen_with_retry(; on_retry, streamcallback=get(kwargs, :streamcallback, nothing), model_name=config.slug) do
        aigen(prompt, config; kwargs...)
    end
end

function aigenerate_with_config(model::String, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               on_retry=nothing,
                               kwargs...)
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(model, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end
    base_api_kwargs = get(kwargs, :api_kwargs, NamedTuple())
    filtered_kwargs = NamedTuple(k => v for (k, v) in pairs(kwargs) if k != :api_kwargs)
    _aigen_with_retry(; on_retry, streamcallback=get(kwargs, :streamcallback, nothing), model_name=model) do
        aigen(prompt, model; filtered_kwargs..., base_api_kwargs...)
    end
end
