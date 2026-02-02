export get_model_context_limit

using OpenRouter: get_model

const DEFAULT_CONTEXT_LIMIT = 200000

"""
    parse_provider_model_slug(model::String) -> (provider::Union{String,Nothing}, model_id::String)

Parse a model slug in "provider:author/model" format.
Returns (provider, model_id) where provider may be nothing if not present.
"""
function parse_provider_model_slug(model::String)
    colon_idx = findfirst(':', model)
    slash_idx = findfirst('/', model)
    # Only parse as provider:model if colon comes before slash
    if colon_idx !== nothing && (slash_idx === nothing || colon_idx < slash_idx)
        provider = lowercase(model[1:colon_idx-1])
        model_id = model[colon_idx+1:end]
        return provider, model_id
    end
    return nothing, model
end

"""
    get_model_context_limit(model::String) -> Int

Get the context limit for a model using OpenRouter.jl's model database.
Returns 200000 (Claude default) if model not found or context_length unavailable.

Handles model slugs in "provider:author/model" format:
1. Extracts provider and model_id from the slug
2. Looks up the model in OpenRouter's cache
3. If provider specified, finds that provider's endpoint and uses its context_length
4. Falls back to model's base context_length, then DEFAULT_CONTEXT_LIMIT
"""
function get_model_context_limit(model::String)
    isempty(model) && return DEFAULT_CONTEXT_LIMIT

    # Parse provider and model_id from slug
    provider, model_id = parse_provider_model_slug(model)

    try
        # Fetch with endpoints if we have a specific provider
        cached = get_model(model_id; fetch_endpoints=(provider !== nothing))

        if cached === nothing
            @warn "Model not found in OpenRouter cache" model model_id
            return DEFAULT_CONTEXT_LIMIT
        end

        # If provider specified, try to find that provider's endpoint context_length
        if provider !== nothing && cached.endpoints !== nothing
            for endpoint in cached.endpoints.endpoints
                if lowercase(endpoint.provider_name) == provider ||
                   (endpoint.tag !== nothing && lowercase(endpoint.tag) == provider)
                    if endpoint.context_length !== nothing
                        return endpoint.context_length
                    end
                    break  # Found provider but no context_length, fall through to model default
                end
            end
        end

        # Fall back to model's base context_length
        if cached.model.context_length !== nothing
            return cached.model.context_length
        end

        @warn "No context_length found for model" model model_id provider
    catch e
        @warn "Failed to get model context limit from OpenRouter" model model_id exception=e
    end

    return DEFAULT_CONTEXT_LIMIT
end
