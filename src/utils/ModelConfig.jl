export ModelConfig, aigenerate_with_config

# Import all available schemas from PromptingTools
using PromptingTools: AbstractPromptSchema, OpenAISchema, CustomOpenAISchema, LocalServerOpenAISchema,
    MistralOpenAISchema, DatabricksOpenAISchema, AzureOpenAISchema, FireworksOpenAISchema,
    TogetherOpenAISchema, GroqOpenAISchema, DeepSeekOpenAISchema, OpenRouterOpenAISchema,
    CerebrasOpenAISchema, SambaNovaOpenAISchema, XAIOpenAISchema, GoogleOpenAISchema,
    MiniMaxOpenAISchema, OllamaSchema, ChatMLSchema, OllamaManagedSchema, GoogleSchema,
    AnthropicSchema, ShareGPTSchema, TracerSchema, SaverSchema

"""
    ModelConfig

Configuration specification for AI models with default parameters and metadata.
"""
@kwdef mutable struct ModelConfig
    name::String
    schema::Union{AbstractPromptSchema, Nothing} = nothing
    cost_of_token_prompt::Float64 = 0.0
    cost_of_token_generation::Float64 = 0.0
    default_api_kwargs::NamedTuple = NamedTuple()
    default_kwargs::NamedTuple = NamedTuple()
    extras::NamedTuple = NamedTuple()
end

# Single responsibility: extract model name from either string or config
get_model_name(model::String) = model
get_model_name(config::ModelConfig) = config.name

# Model-specific logic centralized in ModelConfig
is_openai_reasoning_model(model_name::String) = model_name in ("o3", "o3m", "o4m") || startswith(model_name, "gpt-5")
is_mistral_model(model_name::String) = startswith(model_name, "mistral")
is_claude_model(model_name::String) = model_name == "claude" || startswith(model_name, "claude")
is_grok_model(model_name::String) = startswith(model_name, "grok")

"""
    apply_stop_sequences(model_name::String, api_kwargs::NamedTuple, stop_sequences::Vector{String})

Apply stop sequences to API kwargs based on model type.
"""
function apply_stop_sequences(model_name::String, api_kwargs::NamedTuple, stop_sequences::Vector{String})
    isempty(stop_sequences) && return api_kwargs
    startswith(model_name, "gem") && return api_kwargs  # Gemini doesn't support stop sequences
    is_openai_reasoning_model(model_name) && return api_kwargs  # Reasoning models don't support stop sequences
    is_grok_model(model_name) && return api_kwargs  # Grok models don't support stop sequences
    
    # Different models use different parameter names for stop sequences
    key = startswith(model_name, "claude") ? :stop_sequences : :stop
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
    apply_stop_sequences(config.name, api_kwargs, stop_sequences)
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
    # Merge config defaults with base kwargs first
    merged_kwargs = merge(config.default_api_kwargs, base_api_kwargs)
    
    # Then apply model-specific rules using the string version
    return get_api_kwargs_for_model(config.name, merged_kwargs)
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

    base_api_kwargs = get(kwargs, :api_kwargs, NamedTuple())
    final_api_kwargs = get_api_kwargs_for_model(config, base_api_kwargs)
    
    # Convert kwargs to NamedTuple and merge properly
    kwargs_nt = NamedTuple(kwargs)
    merged_kwargs = merge(config.default_kwargs, kwargs_nt, (; api_kwargs = final_api_kwargs))
    aigenerate(config.schema, prompt; model = config.name, merged_kwargs...)
end

function aigenerate_with_config(model::String, prompt; 
                               request_id::Union{String, Nothing} = nothing,
                               kwargs...)
    if !haskey(kwargs, :api_key)
        # Get API key from global manager
        api_key = get_api_key_for_model(model, request_id, string(prompt))
        !isnothing(api_key) && (kwargs = (;kwargs..., api_key))
    end
    aigenerate(prompt; model, kwargs...)
end

"""
    set_api_key_for_schema!(schema::AbstractPromptSchema, api_key::String)

Set the API key for a specific schema type in PromptingTools.
"""
function set_api_key_for_schema!(schema::Union{AbstractPromptSchema, Nothing}, api_key::String)
    isnothing(schema) && return
    
    if schema isa OpenAISchema
        PromptingTools.OPENAI_API_KEY = api_key
    elseif schema isa CerebrasOpenAISchema
        PromptingTools.CEREBRAS_API_KEY = api_key
    elseif schema isa MistralOpenAISchema
        PromptingTools.MISTRAL_API_KEY = api_key
    elseif schema isa AnthropicSchema
        PromptingTools.ANTHROPIC_API_KEY = api_key
    elseif schema isa GoogleSchema
        PromptingTools.GOOGLE_API_KEY = api_key
    elseif schema isa GroqOpenAISchema
        PromptingTools.GROQ_API_KEY = api_key
    # Add more schema types as needed
    end
end