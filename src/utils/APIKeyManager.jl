export APIKeyManager, get_api_key_for_model, StringApiKey

using OpenRouter: extract_provider_from_model, PROVIDER_INFO
using JSON3
using JLD2
using LLMRateLimiters: CharCountDivTwo, RateLimiterTPM

const DATA_DIR = joinpath(dirname(@__DIR__), "..", "data")
const STATS_FILE = joinpath(DATA_DIR, "credentials_stats.jld2")
const STATS_LOCK = ReentrantLock()

SAFETY_TPM_FACTOR = 1.2

"""
    StringApiKey

Represents an API key with proper sliding window rate limiting.
"""
mutable struct StringApiKey
    key::String
    provider_name::String
    rate_limiter::RateLimiterTPM
    last_save_time::Float64
    save_threshold::Int
    tokens_since_save::Int

    function StringApiKey(key::String, provider_name::String = "openai", max_tokens_per_minute::Int = 1_000_000 )
        rate_limiter = RateLimiterTPM(
            max_tokens = max_tokens_per_minute,
            time_window = 60.0,
            estimation_method = CharCountDivTwo
        )
        new(key, provider_name, rate_limiter, time(), 10, 0)
    end
end

"""
    APIKeyManager

Manages API keys with rate limiting and request routing.
"""
mutable struct APIKeyManager
    provider_to_api_keys::Dict{String, Vector{StringApiKey}}
    request_affinity::Dict{String, Tuple{String, Float64}}
    affinity_window::Float64
    
    function APIKeyManager(affinity_window::Float64 = 300.0)
        new(Dict{String, Vector{StringApiKey}}(),
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
                    "provider_name" => api_key.provider_name,
                    "tokens_used_last_minute" => LLMRateLimiters.current_usage(api_key.rate_limiter),
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

function add_api_keys!(manager::APIKeyManager, provider_name::String, keys::Vector{String}, max_tokens_per_minute::Int = 1_000_000)
    if !haskey(manager.provider_to_api_keys, provider_name)
        manager.provider_to_api_keys[provider_name] = StringApiKey[]
    end
    append!(manager.provider_to_api_keys[provider_name], [StringApiKey(key, provider_name, floor(Int, max_tokens_per_minute / SAFETY_TPM_FACTOR)) for key in keys])
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
    find_api_key_for_request(manager::APIKeyManager, provider_name::String,
                            request_id::Union{String, Nothing}, estimated_tokens::Int)

Find API key with lowest current usage (with sticky routing preference).
"""
function find_api_key_for_request(manager::APIKeyManager, provider_name::String,
                                 request_id::Union{String, Nothing}, estimated_tokens::Int)
    !haskey(manager.provider_to_api_keys, provider_name) && return nothing
    
    api_keys = manager.provider_to_api_keys[provider_name]
    isempty(api_keys) && return nothing

    # 1) Sticky routing if possible
    if !isnothing(request_id) && haskey(manager.request_affinity, request_id)
        key_str, last_t = manager.request_affinity[request_id]
        if time() - last_t <= manager.affinity_window
            # Find the matching key object
            idx = findfirst(k -> k.key == key_str, api_keys)
            if !isnothing(idx) && LLMRateLimiters.can_add_tokens(api_keys[idx].rate_limiter, estimated_tokens)
                return api_keys[idx]
            end
        end
    end

    # 2) Simply choose the key with lowest current usage
    return argmin(k -> LLMRateLimiters.current_usage(k.rate_limiter), api_keys)
end

"""
    initialize_from_env!(manager::APIKeyManager)

Initialize API keys from environment variables using OpenRouter provider registry.
"""
function initialize_from_env!(manager::APIKeyManager)
    isempty(manager.provider_to_api_keys) || return  # Already initialized

    # Process all providers in the OpenRouter registry
    for (provider_name, provider_info) in PROVIDER_INFO
        if provider_info.api_key_env_var !== nothing
            keys = collect_env_keys(provider_info.api_key_env_var)
            !isempty(keys) && add_api_keys!(manager, provider_name, keys)
        end
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
    
    provider_name = if model isa ModelConfig
        # For ModelConfig, we need to determine provider from the slug
        extract_provider_from_model(model.slug)
    else
        extract_provider_from_model(model)
    end
    
    est = LLMRateLimiters.estimate_tokens(prompt, CharCountDivTwo)
    key_obj = find_api_key_for_request(manager, provider_name, request_id, est)
    
    isnothing(key_obj) && return nothing
    
    # Update usage and affinity
    update_usage!(key_obj, est)
    !isnothing(request_id) && (manager.request_affinity[request_id] = (key_obj.key, time()))
    
    return key_obj.key
end