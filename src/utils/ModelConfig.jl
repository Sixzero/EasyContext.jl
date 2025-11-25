export ModelConfig, aigenerate_with_config
using OpenRouter: extract_provider_from_model, ModelConfig
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
_get_provider(model_name::String) = extract_provider_from_model(model_name)

# Model-specific logic centralized in ModelConfig (now purely provider-based)
is_openai_reasoning_model(model_name::String) =
    _get_provider(model_name) == "openai"

is_mistral_model(model_name::String) = _get_provider(model_name) == "mistral"

is_claude_model(model_name::String) = _get_provider(model_name) == "anthropic"

is_grok_model(model_name::String) = _get_provider(model_name) == "xai"

# Gemini detection (used only for stop-sequence support)
is_gemini_model(model_name::String) =
    _get_provider(model_name) in ("google", "google-ai-studio")

"""
    apply_stop_sequences(model_name::String, api_kwargs::NamedTuple, stop_sequences::Vector{String})

Apply stop sequences to API kwargs based on model type.
"""
function apply_stop_sequences(model_name::String, api_kwargs::NamedTuple, stop_sequences::Vector{String})
    isempty(stop_sequences) && return api_kwargs
    is_gemini_model(model_name) && return api_kwargs            # Gemini doesn't support stop sequences
    is_openai_reasoning_model(model_name) && return api_kwargs  # Reasoning models don't support stop sequences
    is_grok_model(model_name) && return api_kwargs              # Grok models don't support stop sequences
    
    # Different models use different parameter names for stop sequences
    key = is_claude_model(model_name) ? :stop_sequences : :stop
    merge(api_kwargs, (; key => stop_sequences))
end

"""
    apply_stop_sequences(config::ModelConfig, api_kwargs::NamedTuple, stop_sequences::Vector{String})

Apply stop sequences for ModelConfig.
"""
apply_stop_sequences(config::ModelConfig, api_kwargs::NamedTuple, stop_sequences::Vector{String}) = begin
    if config.schema isa CerebrasOpenAISchema
        # @info "CerebrasOpenAISchema does not support stop sequences with streaming"
        return api_kwargs
    end
    apply_stop_sequences(config.slug, api_kwargs, stop_sequences)
end

"""
    get_api_kwargs_for_model(model_name::String, base_api_kwargs)

Get model-specific API kwargs for string model names.
"""
function get_api_kwargs_for_model(model_name::String, base_api_kwargs::NamedTuple)
    # Start with base kwargs or default reasoning model behavior
    api_kwargs = is_openai_reasoning_model(model_name) ? NamedTuple() : base_api_kwargs
    
    # Apply Claude-specific settings
    is_claude_model(model_name) && (api_kwargs = merge(api_kwargs, (; max_tokens = 16000)))
    
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
function aigenerate_with_config(config::ModelConfig, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               kwargs...)
    # Get API key from global manager
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(config, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end

    aigen(prompt, config; kwargs...)
end

function aigenerate_with_config(model::String, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               kwargs...)
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(model, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end
    base_api_kwargs = get(kwargs, :api_kwargs, NamedTuple())
    filtered_kwargs = NamedTuple(k => v for (k, v) in pairs(kwargs) if k != :api_kwargs)
    aigen(prompt, model; filtered_kwargs..., base_api_kwargs...)
end
