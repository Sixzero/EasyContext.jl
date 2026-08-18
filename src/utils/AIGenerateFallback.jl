export AIGenerateFallback, ModelState, try_generate
export mark_model_unavailable!, is_model_available, model_unavailable_reason

"""
    ModelState

Tracks the state and health of an AI model.
"""
Base.@kwdef mutable struct ModelState
    failures::Int = 0
    last_error_type::Union{Nothing,Type} = nothing
    last_error_time::Float64 = 0.0
    available::Bool = true
    reason::String = ""
    runtimes::Vector{Float64} = Float64[]
    recovery_time::Int = 300  # seconds until an unavailable model is retried
end

"""
    AIGenerateFallback

Manages fallback and retry logic for AI model generation.
"""
Base.@kwdef mutable struct AIGenerateFallback{T}
    models::T
    states::Dict{String,ModelState} = Dict{String,ModelState}()
    readtimeout::Int = 30
end

# Helper functions
disable_model!(state::ModelState, reason::String) = (state.available = false; state.reason = reason; state.last_error_time = time())

function maybe_recover_model!(state::ModelState, recovery_time::Int=state.recovery_time)
    if !state.available && (time() - state.last_error_time) > recovery_time
        state.available = true
        state.reason = ""
        state.failures = 0
    end
end

# ============ Global model availability (provider pool cooldowns) ============
# Process-global registry keyed by model name (as passed to aigenerate_with_config).
# Records stall / pool-exhaustion cooldowns for logs and user-facing messages —
# we do NOT silently switch the user onto another provider.
const GLOBAL_MODEL_STATES = Dict{String,ModelState}()
const GLOBAL_MODEL_STATES_LOCK = ReentrantLock()

const POOL_EXHAUSTED_DEFAULT_COOLDOWN = 1800  # when the error carries no parseable "retry in X"

function mark_model_unavailable!(model_name::AbstractString, reason::AbstractString; recovery_time::Int=POOL_EXHAUSTED_DEFAULT_COOLDOWN)
    lock(GLOBAL_MODEL_STATES_LOCK) do
        state = get!(GLOBAL_MODEL_STATES, String(model_name), ModelState())
        # Never shorten a stronger cooldown already in force (e.g. a 180s stall
        # mark racing an hours-long pool-exhaustion cooldown on the same model).
        if !state.available && state.last_error_time + state.recovery_time > time() + recovery_time
            return
        end
        state.recovery_time = recovery_time
        disable_model!(state, String(reason))
    end
end

function is_model_available(model_name::AbstractString)
    lock(GLOBAL_MODEL_STATES_LOCK) do
        state = get(GLOBAL_MODEL_STATES, String(model_name), nothing)
        state === nothing && return true
        maybe_recover_model!(state)
        state.available
    end
end

function model_unavailable_reason(model_name::AbstractString)
    lock(GLOBAL_MODEL_STATES_LOCK) do
        state = get(GLOBAL_MODEL_STATES, String(model_name), nothing)
        state === nothing ? "" : state.reason
    end
end

"""
Mark `model_name` unavailable when `e` is a provider pool-exhaustion error
(auth_unavailable / usage_limit_reached), for the duration parsed from its
"retry in Xh Ym Zs" cooldown. Returns true if marked.
"""
function maybe_mark_pool_exhausted!(model_name::AbstractString, e)
    msg = sprint(showerror, e)
    _is_pool_exhausted_error(lowercase(msg)) || return false
    recovery_time = something(parse_retry_after_seconds(msg), POOL_EXHAUSTED_DEFAULT_COOLDOWN)
    mark_model_unavailable!(model_name, first(msg, 300); recovery_time)
    @warn "Provider pool exhausted — model marked unavailable" model=model_name recovery_time
    true
end

# Stalls are provider blips, not hours-long quota cooldowns: keep the model out
# of rotation just long enough to ride out the incident window.
const STALL_COOLDOWN = 180  # seconds

"""
Mark `model_name` briefly unavailable when `e` is a stream stall
(StreamIdleTimeoutError). Returns true if marked.
"""
function maybe_mark_stalled!(model_name::AbstractString, e)
    _is_stall_error(e) || return false
    mark_model_unavailable!(model_name, first(sprint(showerror, e), 300); recovery_time=STALL_COOLDOWN)
    @warn "Stream stalled — model marked unavailable briefly" model=model_name cooldown=STALL_COOLDOWN
    true
end

# Rewrites an upstream provider rate-limit (429) into a clear TODOforAI-side
# message, since the shared API key's per-minute budget is a TODOforAI capacity
# limit, not something the user can fix by adding funds.
is_rate_limit_error(e) = e isa HTTP.Exceptions.StatusError && e.status == 429

const RATE_LIMIT_MESSAGE = "TODOforAI API key rate limit reached (too many requests per minute on the shared key). " *
    "This is a capacity limit, not a balance issue — it clears on its own shortly. " *
    "If it persists, please contact support@todofor.ai."

function handle_error!(state::ModelState, e::Exception, model::String="X")
    state.failures += 1
    state.last_error_type = typeof(e)
    state.last_error_time = time()
    state.reason = is_rate_limit_error(e) ? RATE_LIMIT_MESSAGE : "$e"
    
    return state.reason
end

# Single model attempt - DRY principle
function attempt_generate(model_or_config, prompt, manager, state; condition=nothing, kwargs...)
    model_name = get_model_name(model_or_config)
    readtimeout = is_openai_reasoning_model(model_name) ? 30 : manager.readtimeout
    
    res = aigenerate_with_config(model_or_config, prompt; 
        # http_kwargs=(; readtimeout), 
        kwargs...)
    
    # Check condition if provided
    if !isnothing(condition) && !condition(res)
        error("Generated content did not meet condition criteria")
    end
    
    res
end

"""
    try_generate(manager::AIGenerateFallback, prompt; condition=nothing, kwargs...)

Attempts to generate AI response with retry and fallback logic.
"""
function try_generate(manager::AIGenerateFallback, prompt; condition=nothing, api_kwargs=NamedTuple(), retries=3, kwargs...)
    models = manager.models isa AbstractVector ? manager.models : [manager.models]
    
    for model_or_config in models
        model_name = get_model_name(model_or_config)
        state = get!(manager.states, model_name, ModelState())
        maybe_recover_model!(state)
        !state.available && continue
        
        # Retry logic for single model
        for attempt in 1:retries
            result, time_taken = @timed try
                attempt_generate(model_or_config, prompt, manager, state; condition, api_kwargs..., kwargs...)
            catch e
                e isa InterruptException && rethrow(e)
                reason = handle_error!(state, e, model_name)
                
                if attempt == retries
                    disable_model!(state, "Failed after $retries retries: $reason")
                    break
                end
                
                sleep_time = 2^attempt
                @warn "Model attempt $attempt/$retries: $reason Sleeping for $sleep_time seconds"
                (is_rate_limit_error(e) || (e isa HTTP.Exceptions.StatusError && e.status == 529)) && sleep(sleep_time)
                e isa TimeoutError && (manager.readtimeout *= 2)
                continue
            end
            
            push!(state.runtimes, time_taken)
            return result
        end
    end
    
    # All models failed
    model_names = [get_model_name(m) for m in models]
    reasons = ["$m: $(manager.states[m].reason)" for m in model_names if haskey(manager.states, m)]
    error("All models failed:\n" * join(reasons, "\n"))
end