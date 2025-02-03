
export AIGenerateFallback, ModelState, try_generate

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
end

"""
    AIGenerateFallback{T<:Union{String,Vector{String}}}

Manages fallback and retry logic for AI model generation.
"""
Base.@kwdef mutable struct AIGenerateFallback{T<:Union{String,Vector{String}}}
    models::T
    states::Dict{String,ModelState} = Dict{String,ModelState}()
    readtimeout::Int = 15
end

# Helper functions
disable_model!(state::ModelState, reason::String) = (state.available = false; state.reason = reason; state.last_error_time = time())

function maybe_recover_model!(state::ModelState, recovery_time::Int=300)
    if !state.available && (time() - state.last_error_time) > recovery_time
        state.available = true
        state.reason = ""
        state.failures = 0
    end
end

function handle_error!(state::ModelState, e::Exception, model::String="X")
    state.failures += 1
    state.last_error_type = typeof(e)
    state.last_error_time = time()
    
    e isa TimeoutError && return "Model '$model': Timeout"
    e isa HTTP.Exceptions.StatusError && e.status == 429 && return "Model '$model': Rate limited (429)"
    return "Model '$model': Error: $(typeof(e))"
end

"""
    try_generate(manager::AIGenerateFallback, prompt; kwargs...)

Attempts to generate AI response with retry and fallback logic.
"""
function try_generate(manager::AIGenerateFallback{String}, prompt; api_kwargs, kwargs...)
    model = manager.models
    state = get!(manager.states, model, ModelState())
    maybe_recover_model!(state)
    manager.readtimeout *= 4 # we actually should let it run longer, since there is no other model to try...

    if model == "o3m" # TODO: no temperature support for o3m
        api_kwargs = (; )
    end

    for attempt in 1:3
        result, time = @timed try
            aigenerate(prompt; model, http_kwargs=(; readtimeout=manager.readtimeout), api_kwargs, kwargs...)
        catch e
            reason = handle_error!(state, e, model)
            attempt == 3 && (disable_model!(state, "Failed after 3 retries: $reason"); rethrow(e))
            sleep_time = 2^attempt
            @warn "Model attempt $attempt/3: $reason Sleeping for $sleep_time seconds"
            e isa HTTP.Exceptions.StatusError && e.status == 429 && sleep(sleep_time)
            e isa TimeoutError && (manager.readtimeout *= 2) # NOTE: This is not a good idea, but it's a quick fix
            continue
        end
        push!(state.runtimes, time)
        return result
    end
end

function try_generate(manager::AIGenerateFallback{Vector{String}}, prompt; kwargs...)
    for model in manager.models
        state = get!(manager.states, model, ModelState())
        maybe_recover_model!(state)
        !state.available && continue
        
        result, time = @timed try
            aigenerate(prompt; model, http_kwargs=(; readtimeout=manager.readtimeout), kwargs...)
        catch e
            reason = handle_error!(state, e, model)
            disable_model!(state, reason)
            continue
        end
        push!(state.runtimes, time)
        return result
    end
    reasons = ["$m: $(manager.states[m].reason)" for m in manager.models if haskey(manager.states, m)]
    error("All models failed:\n" * join(reasons, "\n"))
end
