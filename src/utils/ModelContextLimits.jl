export get_model_context_limit

using OpenRouter: get_model

const DEFAULT_CONTEXT_LIMIT = 200000

"""
    get_model_context_limit(model::String) -> Int

Get the context limit for a model using OpenRouter.jl's model database.
Returns 200000 (Claude default) if model not found or context_length unavailable.

Uses OpenRouter.jl's built-in caching - no separate JSON file needed.
"""
function get_model_context_limit(model::String)
    isempty(model) && return DEFAULT_CONTEXT_LIMIT

    try
        cached = get_model(model; fetch_endpoints=false)
        if cached !== nothing && cached.model.context_length !== nothing
            return cached.model.context_length
        else
            @warn "Model not found in OpenRouter cache" model
        end
    catch e
        @warn "Failed to get model context limit from OpenRouter" model exception=e
    end

    return DEFAULT_CONTEXT_LIMIT
end
