export get_model_context_limit, set_models_data_path!, load_model_context_limits, get_models_data_path

using JSON3

const _MODEL_CONTEXT_CACHE = Ref{Union{Nothing, Dict{String, Int}}}(nothing)
const _MODELS_DATA_PATH = Ref{String}("")

"""
    set_models_data_path!(path::String)

Set the path to models_data.json. Clears cache to force reload.
"""
function set_models_data_path!(path::String)
    _MODELS_DATA_PATH[] = path
    _MODEL_CONTEXT_CACHE[] = nothing
end

"""
    get_models_data_path() -> String

Get the path to models_data.json. Checks in order:
1. Explicitly set path via set_models_data_path!
2. MODELS_DATA_PATH environment variable
3. Default path in EasyContext.jl/data
"""
function get_models_data_path()
    !isempty(_MODELS_DATA_PATH[]) && return _MODELS_DATA_PATH[]

    env_path = get(ENV, "MODELS_DATA_PATH", "")
    !isempty(env_path) && return env_path

    default_path = joinpath(@__DIR__, "..", "..", "data", "models_data.json")
    isfile(default_path) && return default_path

    return ""
end

"""
    load_model_context_limits() -> Dict{String, Int}

Load and parse models_data.json, building a model_id -> context_length mapping.
Takes the maximum context_length across all endpoints for each model.
Results are cached.
"""
function load_model_context_limits()
    !isnothing(_MODEL_CONTEXT_CACHE[]) && return _MODEL_CONTEXT_CACHE[]

    path = get_models_data_path()
    if isempty(path) || !isfile(path)
        @warn "models_data.json not found" path
        _MODEL_CONTEXT_CACHE[] = Dict{String, Int}()
        return _MODEL_CONTEXT_CACHE[]
    end

    try
        data = JSON3.read(read(path, String))
        limits = Dict{String, Int}()

        for model in get(data, :models, [])
            model_id = get(model, :id, "")
            isempty(model_id) && continue

            max_context = 0
            for endpoint in get(model, :endpoints, [])
                ctx_len = get(endpoint, :context_length, 0)
                max_context = max(max_context, ctx_len)
            end

            max_context > 0 && (limits[model_id] = max_context)
        end

        @info "Loaded model context limits" path num_models=length(limits)
        _MODEL_CONTEXT_CACHE[] = limits
        return limits
    catch e
        @error "Failed to load models_data.json" path exception=e
        _MODEL_CONTEXT_CACHE[] = Dict{String, Int}()
        return _MODEL_CONTEXT_CACHE[]
    end
end

"""
    get_model_context_limit(model::String) -> Int

Get the context limit for a model from models_data.json.
Returns 200000 (Claude default) if model not found.
Supports exact match and prefix matching.
"""
function get_model_context_limit(model::String)
    isempty(model) && return 200000

    limits = load_model_context_limits()

    haskey(limits, model) && return limits[model]

    # Prefix match
    model_lower = lowercase(model)
    for (key, limit) in limits
        if startswith(lowercase(key), model_lower) || startswith(model_lower, lowercase(key))
            return limit
        end
    end

    return 200000
end
