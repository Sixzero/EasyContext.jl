"""
    setup_api_key_rotation(base_keys::Dict{String, Vector{String}})

Sets up API key rotation by setting numbered environment variables.

# Example
```julia
setup_api_key_rotation(Dict(
    "OPENAI_API_KEY" => ["sk-key1", "sk-key2", "sk-key3"],
    "ANTHROPIC_API_KEY" => ["sk-ant-key1", "sk-ant-key2"]
))
```
"""
function setup_api_key_rotation(base_keys::Dict{String, Vector{String}})
    for (base_key, keys) in base_keys
        for (i, key) in enumerate(keys)
            if i == 1
                ENV[base_key] = key  # Set the primary key
            else
                ENV["$(base_key)_$(i)"] = key  # Set numbered backup keys
            end
        end
        @info "Set up $(length(keys)) API keys for rotation: $base_key"
    end
end

"""
    load_api_keys_from_file(filepath::String)

Loads API keys from a JSON file for rotation setup.
Expected format:
```json
{
    "OPENAI_API_KEY": ["sk-key1", "sk-key2"],
    "ANTHROPIC_API_KEY": ["sk-ant-key1", "sk-ant-key2"]
}
```
"""
function load_api_keys_from_file(filepath::String)
    if isfile(filepath)
        keys_data = JSON3.read(read(filepath, String))
        setup_api_key_rotation(Dict(string(k) => Vector{String}(v) for (k, v) in keys_data))
    else
        @warn "API keys file not found: $filepath"
    end
end

"""
    get_api_key_env_var(schema_type::Type) -> String

Maps schema types to their corresponding environment variable names for API key rotation.
"""
function get_api_key_env_var(schema_type::Type)
    schema_to_env = Dict(
        :OpenAISchema => "OPENAI_API_KEY",
        :CustomOpenAISchema => "OPENAI_API_KEY",
        :LocalServerOpenAISchema => "OPENAI_API_KEY",
        :MistralOpenAISchema => "MISTRAL_API_KEY",
        :DatabricksOpenAISchema => "DATABRICKS_API_KEY",
        :AzureOpenAISchema => "AZURE_OPENAI_API_KEY",
        :FireworksOpenAISchema => "FIREWORKS_API_KEY",
        :TogetherOpenAISchema => "TOGETHER_API_KEY",
        :GroqOpenAISchema => "GROQ_API_KEY",
        :DeepSeekOpenAISchema => "DEEPSEEK_API_KEY",
        :OpenRouterOpenAISchema => "OPENROUTER_API_KEY",
        :CerebrasOpenAISchema => "CEREBRAS_API_KEY",
        :SambaNovaOpenAISchema => "SAMBANOVA_API_KEY",
        :XAIOpenAISchema => "XAI_API_KEY",
        :GoogleOpenAISchema => "GOOGLE_API_KEY",
        :GoogleSchema => "GOOGLE_API_KEY",
        :MiniMaxOpenAISchema => "MINIMAX_API_KEY",
        :MoonshotOpenAISchema => "MOONSHOT_API_KEY",
        :AnthropicSchema => "ANTHROPIC_API_KEY"
    )
    
    schema_name = nameof(schema_type)
    return get(schema_to_env, schema_name, "OPENAI_API_KEY")  # Default fallback
end

"""
    is_quota_exceeded_error(e::Exception) -> Bool

Check if the error indicates quota/rate limit exceeded.
"""
function is_quota_exceeded_error(e::Exception)
    if e isa HTTP.Exceptions.StatusError
        return e.status == 429 || 
               (hasfield(typeof(e), :response) && 
                occursin(r"(?i)quota|limit|rate.?limit", string(e.response)))
    end
    return occursin(r"(?i)quota|limit|rate.?limit", string(e))
end

"""
    rotate_api_key!(manager::AIGenerateFallback, model_name::String, schema_type::Type) -> Bool

Attempts to rotate to the next available API key for the given schema type.
Returns true if rotation was successful, false otherwise.
"""
function rotate_api_key!(manager::AIGenerateFallback, model_name::String, schema_type::Type)
    !manager.api_key_rotation && return false
    
    env_var = get_api_key_env_var(schema_type)
    state = manager.states[model_name]
    
    # Look for numbered API keys (e.g., OPENAI_API_KEY_2, OPENAI_API_KEY_3, etc.)
    next_index = state.current_api_key_index + 1
    next_key_var = "$(env_var)_$(next_index)"
    
    if haskey(ENV, next_key_var)
        try
            # Update PromptingTools global variable only
            global_var_name = Symbol(env_var)
            if isdefined(PromptingTools, global_var_name)
                setproperty!(PromptingTools, global_var_name, ENV[next_key_var])
            end
            state.current_api_key_index = next_index
            @info "Rotated API key for $model_name to $(next_key_var)"
            return true
        catch e
            @warn "Failed to rotate API key for $model_name" exception=e
            return false
        end
    end

    # Try to reset back to index 1 (base env var)
    if state.current_api_key_index > 1 && haskey(ENV, env_var)
        try
            global_var_name = Symbol(env_var)
            if isdefined(PromptingTools, global_var_name)
                setproperty!(PromptingTools, global_var_name, ENV[env_var])
            end
            state.current_api_key_index = 1
            @info "Reset API key for $model_name back to $(env_var)"
            return true
        catch e
            @warn "Failed to reset API key for $model_name" exception=e
            return false
        end
    end
    
    return false
end
