export ModelConfig, aigenerate_with_config, _is_context_overflow_error, parse_context_overflow
using OpenRouter: extract_provider_from_model, ModelConfig, StreamIdleTimeoutError, ModelRefusalError
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
# CLIProxyAPI pool exhaustion (every OAuth credential for a provider cooling down)
# arrives in one of two shapes:
#   API Error (503): auth_unavailable: no auth available; last upstream error:
#   {"error":{"type":"usage_limit_reached","plan_type":"prolite","resets_at":...}}
#   (status 429); retry in 42h8m45s (providers=codex, model=gpt-5.6-sol(high))
#   API Error (429): {"error":{"code":"model_cooldown","message":"All credentials for
#   model gpt-5.6-sol(high) are cooling down","reset_time":"42h8m45s","reset_seconds":...}}
# plus our own gateway's sanitized relay of either ("temporarily at capacity").
# It stays transient like any other 429 — CLIProxyAPI rotates credentials on its
# side, so a retry can land on a live one. Detection exists only to replace the
# raw upstream blob (it carries OUR account internals) with a user-facing message.
# Callers lowercase the message.
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
# LB routing to a bad node). The model gets its short cooldown only after the
# FINAL failed attempt.
#
# But a stall retry is expensive: one attempt costs a WHOLE first-chunk window
# (the caller sets that policy — TODOforAI uses 120s, since on the CLIProxyAPI
# codex path no byte arrives before the model's first reasoning delta), and it
# is silent while it burns. Worse, the two failure modes it can hit are both
# poorly served by three attempts: a dead upstream is fixed by ONE fresh
# connection, and a model that is simply slow to first token re-hits the same
# wall with the same prompt every time. So stalls get their own, tighter
# attempt budget (AIGEN_MAX_STALL_ATTEMPTS) instead of the generic one, which
# stays as-is for errors that fail fast (429/502/reset/EOF).
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

# Deliberate allowlist for model switching, not the broader same-model retry rule.
# Called ONLY around inference, never around a tool or a whole work loop.
_is_capacity_fallback_error(e) = !(e isa ModelRefusalError) && _is_capacity_fallback_error(sprint(showerror, e))
function _is_capacity_fallback_error(msg::AbstractString)
    m = lowercase(msg)
    any(p -> occursin(p, m), ("invalid_request", "invalid request", "invalid_api_key",
        "authentication", "unauthorized", "permission_denied", "permission denied",
        "insufficient", "billing", "payment", "balance", "quota", "credit balance",
        "context_length", "prompt is too long", "tool", "content_filter")) && return false
    occursin(r"(?:status\s+|\()(?:400|401|402|403|404|422)\b", m) && return false
    _is_pool_exhausted_error(m) || occursin(r"\boverloaded_error\b", m) ||
        occursin(r"(?:status\s+|\()(?:502|503|504|529)\b", m)
end

const AIGEN_MAX_RETRIES = 3

# Total attempts allowed for a pre-first-chunk stall (see the stall comment
# above): one resend on a fresh connection, then fail. Deliberately below
# AIGEN_MAX_RETRIES — each stall attempt burns a full, silent first-chunk
# window, so a third one mostly just delays the error the user must act on.
const AIGEN_MAX_STALL_ATTEMPTS = 2

# Context overflow: the request was rejected because the prompt exceeds the model's
# context window (Anthropic "prompt is too long: N tokens > M maximum", OpenAI
# "maximum context length ... your messages resulted in N tokens", Google/OpenRouter
# variants). A plain resend is guaranteed to fail identically, so this is NOT a
# transient error — it is only recoverable by SHRINKING the conversation first, which
# `_aigen_with_retry` cannot do (it has no session). Detection lives here next to the
# other error classifiers; the recovery is in FluidAgent.work, which owns the session.
# Deliberately NARROW: recovery mutates the session (summarize + truncate), so a
# false positive destroys history to "fix" something else. Generic size complaints
# ("request too large") are excluded — they are usually request-BYTE or media limits,
# which shrinking text cannot fix and which have their own failure paths.
_is_context_overflow_error(e) = _is_context_overflow_error(sprint(showerror, e))
function _is_context_overflow_error(msg::AbstractString)
    m = lowercase(msg)
    any(p -> occursin(p, m), (
        "prompt is too long", "context_length_exceeded", "maximum context length",
        "context length exceeded", "reduce the length of the messages",
    )) && return true
    # Looser phrasings only count when the message also proves it is about TOKENS.
    occursin("token", m) && any(p -> occursin(p, m), ("context window", "too many tokens", "input is too long"))
end

# Per-request image COUNT cap (e.g. DeepInfra/vLLM "Too many images in request: 31 > 30").
# Unrelated to tokens, so it never triggers compaction: only dropping older images fixes it.
# Returns how many images must go, or nothing. Requires the exact "N > M" shape so a
# stray mention of the phrase (quoted body, 429 text) never deletes images.
function image_count_excess(e)
    m = match(r"too many images in request:\s*(\d+)\s*>\s*(\d+)"i, sprint(showerror, e))
    m === nothing && return nothing
    sent, limit = parse.(Int, m.captures)
    sent > limit ? sent - limit : nothing
end

"""
    parse_context_overflow(msg) -> Union{Nothing,@NamedTuple{used::Int, limit::Int}}

Pull the exact token counts out of a context-overflow error, e.g.
`prompt is too long: 4210492 tokens > 1000000 maximum`. This is the ONLY place the
provider's true context size is ever observable on a failed call — the cutter's own
estimate is chars/2 and it normally learns the real number from a SUCCESSFUL
response, which by definition never arrives here. Returns `nothing` when the message
carries no usable pair (the caller then falls back to its configured limit).
"""
function parse_context_overflow(msg::AbstractString)
    # DeepInfra reports input + reserved output against the total window. Keep the
    # input count as the anchor and subtract output from the learned INPUT limit.
    m = match(r"maximum context length is\s*(\d[\d,_]*)\s*tokens.*?requested\s*(\d[\d,_]*)\s*output tokens.*?prompt contains(?: at least)?\s*(\d[\d,_]*)\s*input tokens"is, msg)
    if m !== nothing
        window, output, used = (c -> parse(Int, replace(c, "," => "", "_" => ""))).(m.captures)
        limit = window - output
        return limit > 0 ? (; used, limit) : nothing
    end
    m = match(r"(\d[\d,_]*)\s*tokens?\s*>\s*(\d[\d,_]*)"i, msg)
    m === nothing && (m = match(r"maximum context length is\s*(\d[\d,_]*)\s*tokens.*?resulted in\s*(\d[\d,_]*)"is, msg))
    m === nothing && return nothing
    a, b = (c -> parse(Int, replace(c, "," => "", "_" => ""))).(m.captures)
    used, limit = max(a, b), min(a, b)   # order differs per provider; the bigger one is what we sent
    limit > 0 ? (; used, limit) : nothing
end

# Process-local circuit breaker. Keys retain provider + model, strip thinking:
# pool exhaustion can be model-specific; never disable a whole provider by guess.
struct CapacityCooldownError <: Exception end
Base.showerror(io::IO, ::CapacityCooldownError) = print(io, "Model temporarily at capacity (five-minute retry cooldown)")
const CAPACITY_RETRY_LOCK = ReentrantLock()
const CAPACITY_RETRY_STATE = Dict{String,Tuple{Float64,Union{Task,Nothing}}}()
const CAPACITY_RETRY_ACTIVE = Threads.Atomic{Int}(0)  # == length(CAPACITY_RETRY_STATE); normal calls skip the lock while 0
const CAPACITY_RETRY_SECONDS = 300.0
capacity_retry_key(model) = replace(get_model_name(model), r"\([^()]*\)$" => "")
capacity_clock() = time_ns() / 1e9

# With no known outage, ordinary calls remain concurrent. Once an outage is
# observed, one task owns the retry/probe; all others fail fast into fallback.
function capacity_retry_enter!(key; failure=false, now=capacity_clock())
    !failure && CAPACITY_RETRY_ACTIVE[] == 0 && return
    lock(CAPACITY_RETRY_LOCK) do
        state = get(CAPACITY_RETRY_STATE, key, nothing)
        if state === nothing
            if failure
                CAPACITY_RETRY_STATE[key] = (now + CAPACITY_RETRY_SECONDS, current_task())
                Threads.atomic_add!(CAPACITY_RETRY_ACTIVE, 1)
            end
            return
        end
        until, owner = state
        owner === current_task() && failure && return
        (owner !== nothing || now < until) && throw(CapacityCooldownError())
        CAPACITY_RETRY_STATE[key] = (now + CAPACITY_RETRY_SECONDS, current_task())
    end
end

function capacity_retry_finish!(key; failed=false, now=capacity_clock())
    CAPACITY_RETRY_ACTIVE[] == 0 && return
    lock(CAPACITY_RETRY_LOCK) do
        state = get(CAPACITY_RETRY_STATE, key, nothing)
        state === nothing && return
        state[2] === current_task() || return
        if failed
            CAPACITY_RETRY_STATE[key] = (now + CAPACITY_RETRY_SECONDS, nothing)
        else
            delete!(CAPACITY_RETRY_STATE, key)
            Threads.atomic_sub!(CAPACITY_RETRY_ACTIVE, 1)
        end
    end
end

function _aigen_with_retry(f::Function; max_retries=AIGEN_MAX_RETRIES, on_retry=nothing, streamcallback=nothing, model_name::String="", capacity_cooldown::Bool=false)
    key = capacity_retry_key(model_name)
    capacity_cooldown && capacity_retry_enter!(key)
    succeeded = false
    try
    for attempt in 1:max_retries
        try
            # A stream callback accumulates chunks in-place across the whole
            # request. On a retry the previous (failed/partial) attempt's chunks
            # are still there and `build_response_body` would rebuild from ALL of
            # them — duplicating or corrupting tool_calls (e.g. the same question
            # asked twice). Reset it so each attempt starts from a clean slate.
            attempt > 1 && streamcallback !== nothing && empty!(streamcallback)
            result = f()
            succeeded = true
            return result
        catch e
            e isa InterruptException && rethrow(e)
            # Safety refusal: the model decided, deterministically. Retrying just
            # burns the same prompt against the same policy.
            e isa ModelRefusalError && rethrow(e)
            # HTTP.RequestError wrapping InterruptException
            hasproperty(e, :error) && e.error isa InterruptException && rethrow(e)
            # Any partial stream may already have executed textual tools or
            # reached the user. Fail fast: clearing chunks cannot undo effects.
            stall = _is_stall_error(e)
            !(streamcallback === nothing || isempty(streamcallback)) && rethrow(e)
            if capacity_cooldown && _is_capacity_fallback_error(e)
                capacity_retry_enter!(key; failure=true)
            end
            # Stalls run on their own (tighter) budget; everything else on the generic one.
            budget = stall ? min(max_retries, AIGEN_MAX_STALL_ATTEMPTS) : max_retries
            if attempt < budget && (stall || _is_transient_error(e) || (capacity_cooldown && _is_capacity_fallback_error(e)))
                sleep_time = 2^attempt
                err_msg = _extract_error_message(e)
                @warn "Transient LLM error (attempt $attempt/$budget), retrying in $(sleep_time)s" exception=(e, catch_backtrace())
                if !isnothing(on_retry)
                    try on_retry(attempt, budget, sleep_time, err_msg) catch ex
                        @warn "on_retry callback failed" exception=(ex, catch_backtrace())
                    end
                end
                sleep(sleep_time)
            else
                # Stall that survived all retries: short cooldown for logs/ETA.
                stall && !isempty(model_name) && maybe_mark_stalled!(model_name, e)
                rethrow(e)
            end
        end
    end
    finally
        capacity_cooldown && capacity_retry_finish!(key; failed=!succeeded)
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
                               capacity_cooldown::Bool=false,
                               kwargs...)
    # Get API key from global manager
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(config, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end

    _aigen_with_retry(; on_retry, capacity_cooldown, streamcallback=get(kwargs, :streamcallback, nothing), model_name=config.slug) do
        aigen(prompt, config; kwargs...)
    end
end

function aigenerate_with_config(model::String, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               on_retry=nothing,
                               capacity_cooldown::Bool=false,
                               kwargs...)
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(model, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end
    base_api_kwargs = get(kwargs, :api_kwargs, NamedTuple())
    filtered_kwargs = NamedTuple(k => v for (k, v) in pairs(kwargs) if k != :api_kwargs)
    _aigen_with_retry(; on_retry, capacity_cooldown, streamcallback=get(kwargs, :streamcallback, nothing), model_name=model) do
        aigen(prompt, model; filtered_kwargs..., base_api_kwargs...)
    end
end
