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
    AIGenerateFallback

Manages fallback and retry logic for AI model generation.
"""
Base.@kwdef mutable struct AIGenerateFallback{T}
    models::T
    states::Dict{String,ModelState} = Dict{String,ModelState}()
    readtimeout::Int = 60
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
    
    return "Model '$model': $e"
end

# Single model attempt - DRY principle
function attempt_generate(model_or_config, prompt, manager, state; condition=nothing, api_kwargs=NamedTuple(), kwargs...)
    model_name = get_model_name(model_or_config)
    readtimeout = is_openai_reasoning_model(model_name) ? 60 : manager.readtimeout
    
    # Prepare kwargs based on model type - now centralized in ModelConfig
    final_api_kwargs, final_kwargs = if model_or_config isa ModelConfig
        merged_api = get_api_kwargs_for_model(model_or_config, api_kwargs)
        merged_kw = merge(model_or_config.default_kwargs, kwargs)
        (merged_api, merged_kw)
    else
        (get_api_kwargs_for_model(model_name, api_kwargs), kwargs)
    end

    res = aigenerate_with_config(model_or_config, prompt; 
        http_kwargs=(; readtimeout), 
        api_kwargs=final_api_kwargs, 
        final_kwargs...)
    
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
                attempt_generate(model_or_config, prompt, manager, state; condition, api_kwargs, kwargs...)
            catch e
                reason = handle_error!(state, e, model_name)
                if attempt == retries
                    disable_model!(state, "Failed after $retries retries: $reason")
                    break
                end
                
                sleep_time = 2^attempt
                @warn "Model attempt $attempt/3: $reason Sleeping for $sleep_time seconds"
                e isa HTTP.Exceptions.StatusError && e.status == 429 && sleep(sleep_time)
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