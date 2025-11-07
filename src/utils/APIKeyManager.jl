export APIKeyManager, get_api_key_for_model, StringApiKey

using PromptingTools
using JSON3
using JLD2
using LLMRateLimiters: CharCountDivTwo, RateLimiterTPM

const DATA_DIR = joinpath(dirname(@__DIR__), "..", "data")
const STATS_FILE = joinpath(DATA_DIR, "credentials_stats.jld2")
const STATS_LOCK = ReentrantLock()

"""
    StringApiKey

Represents an API key with proper sliding window rate limiting.
"""
mutable struct StringApiKey
    key::String
    schema_name::String
    rate_limiter::RateLimiterTPM
    last_save_time::Float64
    save_threshold::Int
    tokens_since_save::Int

    function StringApiKey(key::String, schema_name::String = "OpenAISchema", max_tokens_per_minute::Int = 1_000_000)
        rate_limiter = RateLimiterTPM(
            max_tokens = max_tokens_per_minute,
            time_window = 60.0,
            estimation_method = CharCountDivTwo
        )
        new(key, schema_name, rate_limiter, time(), 10, 0)
    end
end

"""
    APIKeyManager

Manages API keys with rate limiting and request routing.
"""
mutable struct APIKeyManager
    schema_to_api_keys::Dict{Type{<:AbstractPromptSchema}, Vector{StringApiKey}}
    request_affinity::Dict{String, Tuple{String, Float64}}
    affinity_window::Float64
    
    function APIKeyManager(affinity_window::Float64 = 300.0)
        new(Dict{Type{<:AbstractPromptSchema}, Vector{StringApiKey}}(),
            Dict{String,Tuple{String,Float64}}(), affinity_window)
    end
end

# Global instance
const GLOBAL_API_KEY_MANAGER = APIKeyManager()

"""
    save_stats_to_file!(api_key::StringApiKey)

Save API key statistics to JLD2 file asynchronously with partial updates.
"""
function save_stats_to_file!(api_key::StringApiKey)
    @async_showerr begin
        lock(STATS_LOCK) do
            !isdir(DATA_DIR) && mkpath(DATA_DIR)
            key_hash = string(hash(api_key.key))  # Use hash for privacy
            jldopen(STATS_FILE, "a+") do file     # a+ is OK
                haskey(file, key_hash) && delete!(file, key_hash)  # required to overwrite
                file[key_hash] = Dict(
                    "schema_name" => api_key.schema_name,
                    "tokens_used_last_minute" => get_current_usage(api_key),
                    "last_save_time" => api_key.last_save_time
                )
            end
        end
    end
end

"""
    update_usage!(api_key::StringApiKey, tokens::Int)

Update token usage using proper rate limiter and save to file periodically.
"""
function update_usage!(api_key::StringApiKey, tokens::Int)
    LLMRateLimiters.add_tokens!(api_key.rate_limiter, tokens)
    api_key.tokens_since_save += tokens
    
    if api_key.tokens_since_save >= api_key.save_threshold
        api_key.tokens_since_save = 0
        api_key.last_save_time = time()
        save_stats_to_file!(api_key)
    end
end

"""
    get_current_usage(api_key::StringApiKey) -> Int

Get current token usage in the sliding window.
"""
get_current_usage(api_key::StringApiKey) = LLMRateLimiters.current_usage(api_key.rate_limiter)

"""
    can_handle_tokens(api_key::StringApiKey, tokens::Int) -> Bool

Check if the API key can handle the requested number of tokens.
"""
can_handle_tokens(api_key::StringApiKey, tokens::Int) = LLMRateLimiters.can_add_tokens(api_key.rate_limiter, tokens)

"""
    add_api_keys!(manager::APIKeyManager, schema_type::Type{<:AbstractPromptSchema}, keys::Vector{String}, max_tokens_per_minute::Int = 1_000_000)

Add API keys for a specific schema type with rate limiting.
"""
function add_api_keys!(manager::APIKeyManager, schema_type::Type{<:AbstractPromptSchema}, keys::Vector{String}, max_tokens_per_minute::Int = 1_000_000)
    if !haskey(manager.schema_to_api_keys, schema_type)
        manager.schema_to_api_keys[schema_type] = StringApiKey[]
    end
    schema_name = string(nameof(schema_type))
    append!(manager.schema_to_api_keys[schema_type], [StringApiKey(key, schema_name, max_tokens_per_minute) for key in keys])
end

"""
    collect_env_keys(base_env_var::String) -> Vector{String}

Collect all API keys for a given base environment variable (base + numbered variants).
"""
function collect_env_keys(base_env_var::String)
    keys = String[]
    
    # Check base key
    if haskey(ENV, base_env_var) && !isempty(ENV[base_env_var])
        push!(keys, ENV[base_env_var])
    end
    
    # Check numbered keys (KEY_2, KEY_3, etc.)
    for i in 2:100
        env_var = "$(base_env_var)_$i"
        if haskey(ENV, env_var) && !isempty(ENV[env_var])
            push!(keys, ENV[env_var])
        else
            break  # Stop at first missing numbered key
        end
    end
    
    return keys
end

"""
    find_api_key_for_request(manager::APIKeyManager, schema_type::Type{<:AbstractPromptSchema},
                            request_id::Union{String, Nothing}, estimated_tokens::Int)

Find API key with lowest current usage (with sticky routing preference).
"""
function find_api_key_for_request(manager::APIKeyManager, schema_type::Type{<:AbstractPromptSchema},
                                 request_id::Union{String, Nothing}, estimated_tokens::Int)
    !haskey(manager.schema_to_api_keys, schema_type) && return nothing
    
    api_keys = manager.schema_to_api_keys[schema_type]
    isempty(api_keys) && return nothing

    # 1) Sticky routing if possible
    if !isnothing(request_id) && haskey(manager.request_affinity, request_id)
        key_str, last_t = manager.request_affinity[request_id]
        if time() - last_t <= manager.affinity_window
            # Find the matching key object
            idx = findfirst(k -> k.key == key_str, api_keys)
            if !isnothing(idx) && can_handle_tokens(api_keys[idx], estimated_tokens)
                return api_keys[idx]
            end
        end
    end

    # 2) Simply choose the key with lowest current usage
    return argmin(k -> get_current_usage(k), api_keys)
end

"""
    get_model_schema(model::String)

Get the schema for a model from the MODEL_REGISTRY.
"""
function get_model_schema(model::String)
    model_spec = get(PromptingTools.MODEL_REGISTRY, model, nothing)
    return isnothing(model_spec) ? OpenAISchema() : model_spec.schema
end

"""
    get_model_schema(config::ModelConfig)

Get the schema from a ModelConfig.
"""
get_model_schema(config::ModelConfig) = isnothing(config.schema) ? OpenAISchema() : config.schema

"""
    initialize_from_env!(manager::APIKeyManager)

Initialize API keys from environment variables.
"""
function initialize_from_env!(manager::APIKeyManager)
    isempty(manager.schema_to_api_keys) || return  # Already initialized

    # Schema type to environment variable mapping
    schema_env_mapping = [
        (OpenAISchema, "OPENAI_API_KEY"),
        (CerebrasOpenAISchema, "CEREBRAS_API_KEY"),
        (MistralOpenAISchema, "MISTRAL_API_KEY"),
        (AnthropicSchema, "ANTHROPIC_API_KEY"),
        (GoogleSchema, "GOOGLE_API_KEY"),
        (GoogleOpenAISchema, "GOOGLE_API_KEY"),
        (GroqOpenAISchema, "GROQ_API_KEY"),
        (TogetherOpenAISchema, "TOGETHER_API_KEY"),
        (DeepSeekOpenAISchema, "DEEPSEEK_API_KEY"),
        (OpenRouterOpenAISchema, "OPENROUTER_API_KEY"),
        (SambaNovaOpenAISchema, "SAMBANOVA_API_KEY")
    ]

    # Additional environment variables that map to existing schemas
    additional_env_mapping = [
        # ("COHERE_API_KEY", OpenAISchema), #it is worng to assign them to OepnAISchema, also they are embedders and other things.
        # ("TAVILY_API_KEY", OpenAISchema),
        # ("JINA_API_KEY", OpenAISchema),
        # ("VOYAGE_API_KEY", OpenAISchema),
        # ("GEMINI_API_KEY", GoogleSchema)
    ]

    # Process all mappings
    for (schema_type, base_env_var) in schema_env_mapping
        keys = collect_env_keys(base_env_var)
        !isempty(keys) && add_api_keys!(manager, schema_type, keys)
    end

    for (base_env_var, schema_type) in additional_env_mapping
        keys = collect_env_keys(base_env_var)
        !isempty(keys) && add_api_keys!(manager, schema_type, keys)
    end
end

"""
    get_api_key_for_model(model::Union{String, ModelConfig},
                         request_id::Union{String, Nothing} = nothing, prompt::AbstractString = "";
                         manager::APIKeyManager = GLOBAL_API_KEY_MANAGER)

Get the appropriate API key for a model and request with proper rate limiting.
"""
function get_api_key_for_model(model::Union{String, ModelConfig},
                              request_id::Union{String, Nothing} = nothing, prompt::AbstractString = "";
                              manager::APIKeyManager = GLOBAL_API_KEY_MANAGER)
    initialize_from_env!(manager)
    schema = get_model_schema(model)
    schema_type = typeof(schema)
    est = LLMRateLimiters.estimate_tokens(prompt, CharCountDivTwo)
    key_obj = find_api_key_for_request(manager, schema_type, request_id, est)
    
    isnothing(key_obj) && return nothing
    
    # Update usage and affinity
    update_usage!(key_obj, est)
    !isnothing(request_id) && (manager.request_affinity[request_id] = (key_obj.key, time()))
    
    return key_obj.key
end