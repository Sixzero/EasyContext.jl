
# Model state tracking
Base.@kwdef mutable struct ModelState
  failures::Int = 0
  last_error_type::Union{Nothing,Type} = nothing
  last_error_time::Float64 = 0.0
  available::Bool = true
  reason::String = ""  # Track why model was disabled
end

# Fallback to other aigenerate models if the first one fails also retry last model in case there is no other model options
Base.@kwdef mutable struct AIGenerateFallback{T<:Union{String,Vector{String}}}
  models::T
  states::Dict{String,ModelState} = Dict{String,ModelState}()
  readtimeout::Int = 15
end

function disable_model!(state::ModelState, reason::String)
  state.available = false
  state.reason = reason
  state.last_error_time = time()
end

function try_generate(manager::AIGenerateFallback{String}, prompt; kwargs...)
  model = manager.models
  state = get!(manager.states, model, ModelState())
  max_retries = 3
  
  for attempt in 1:max_retries
      try
          return aigenerate(prompt; model, http_kwargs=(; readtimeout=manager.readtimeout), kwargs...)
      catch e
          state.failures += 1
          state.last_error_type = typeof(e)
          state.last_error_time = time()
          
          if e isa TimeoutError
              reason = "Timeout after $(manager.readtimeout)s"
              @warn "Model '$model': $reason. Attempt $attempt of $max_retries"
          elseif e isa HTTP.Exceptions.StatusError && e.status == 429
              reason = "Rate limited (429)"
              @warn "Model '$model': $reason. Attempt $attempt of $max_retries"
              sleep(2^attempt)
          else
              reason = "Failed: $(typeof(e))"
              @warn "Model '$model': $reason. Attempt $attempt of $max_retries"
          end
          attempt == max_retries && rethrow(e)
      end
  end
  disable_model!(state, "Failed after $max_retries retries")
  error("Model '$model' disabled: $(state.reason)")
end

function try_generate(manager::AIGenerateFallback{Vector{String}}, prompt; kwargs...)
  for model in manager.models
      state = get!(manager.states, model, ModelState())
      !state.available && continue
      
      try
          return aigenerate(prompt; model, http_kwargs=(; readtimeout=manager.readtimeout), kwargs...)
      catch e
          state.failures += 1
          state.last_error_type = typeof(e)
          state.last_error_time = time()
          
          if e isa TimeoutError
              disable_model!(state, "Timeout after $(manager.readtimeout)s")
          elseif e isa HTTP.Exceptions.StatusError && e.status == 429
              disable_model!(state, "Rate limited (429)")
          else
              disable_model!(state, "Failed: $(typeof(e))")
          end
          @warn "Model '$model' disabled: $(state.reason)"
      end
  end
  reasons = ["$m: $(manager.states[m].reason)" for m in manager.models if haskey(manager.states, m)]
  error("All models failed:\n" * join(reasons, "\n"))
end
