using Test
using EasyContext
using PromptingTools: OpenAISchema, AbstractPromptSchema, CerebrasOpenAISchema
using OpenRouter: extract_provider_from_model

@testset "API Key Manager Tests" begin
    
    @testset "StringApiKey basic functionality" begin
        api_key = EasyContext.StringApiKey("test_key_123", "openai")
        @test api_key.key == "test_key_123"
        @test api_key.provider_name == "openai"
        @test LLMRateLimiters.current_usage(api_key.rate_limiter) == 0
        @test LLMRateLimiters.can_add_tokens(api_key.rate_limiter, 1000)
    end
    
    @testset "APIKeyManager initialization" begin
        manager = EasyContext.APIKeyManager()
        @test manager.affinity_window == 300.0
        @test isempty(manager.provider_to_api_keys)
        @test isempty(manager.request_affinity)
    end
    
    @testset "extract_provider_from_model" begin
        @test extract_provider_from_model("openai:openai/gpt-4") == "openai"
        @test extract_provider_from_model("anthropic:anthropic/claude-3-5-sonnet") == "anthropic"
        @test extract_provider_from_model("cerebras:meta-llama/llama-3.1-8b") == "cerebras"
        @test extract_provider_from_model("gpt-4") == "openai"  # fallback
        @test extract_provider_from_model("claude") == "openai"  # fallback
    end
    
    @testset "API key registration" begin
        manager = EasyContext.APIKeyManager()
        
        # Add API keys
        EasyContext.add_api_keys!(manager, "openai", ["key1", "key2", "key3"])
        @test length(manager.provider_to_api_keys["openai"]) == 3
        @test manager.provider_to_api_keys["openai"][1].key == "key1"
        @test manager.provider_to_api_keys["openai"][2].key == "key2"
        @test manager.provider_to_api_keys["openai"][3].key == "key3"
    end
    
    @testset "API key selection without request_id" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, "openai", ["key1", "key2"])
        
        # Should return a key (lowest usage initially)
        api_key = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", nothing, "test prompt"; manager=manager)
        @test api_key in ["key1", "key2"]
    end
    
    @testset "API key selection with request_id routing" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, "openai", ["key1", "key2"])
        
        # First request should get a key
        api_key1 = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "request_123", "test prompt"; manager=manager)
        @test api_key1 in ["key1", "key2"]
        
        # Second request with same ID should get same key (within affinity window)
        api_key2 = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "request_123", "another prompt"; manager=manager)
        @test api_key2 == api_key1
        
        # Different request ID might get different key
        api_key3 = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "request_456", "different prompt"; manager=manager)
        @test api_key3 in ["key1", "key2"]
    end

    @testset "Rate limiting behavior" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, "openai", ["key1", "key2"], 10)  # Very low limit for testing
        
        # Use up tokens on both keys
        for i in 1:8
            EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "request_$i", "test prompt with many tokens"; manager=manager)
        end
        
        # Should still work (load balancing between keys)
        api_key = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "request_new", "test prompt"; manager=manager)
        @test api_key in ["key1", "key2"]
    end
    
    @testset "Usage tracking" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, "openai", ["key1"])
        
        # Get the key object to check usage
        key_obj = manager.provider_to_api_keys["openai"][1]
        initial_usage = LLMRateLimiters.current_usage(key_obj.rate_limiter)
        
        # Make a request
        EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "test_request", "hello world test"; manager=manager)
        
        # Usage should have increased
        new_usage = LLMRateLimiters.current_usage(key_obj.rate_limiter)
        @test new_usage > initial_usage
    end
    
    @testset "ModelConfig integration" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, "cerebras", ["cerebras_key1", "cerebras_key2"])
        
        model_config = ModelConfig(
            name = "cerebras:meta-llama/llama-3.1-8b",
            schema = CerebrasOpenAISchema(),
        )
        
        api_key = EasyContext.get_api_key_for_model(model_config, "test_request", "hello world"; manager=manager)
        @test api_key in ["cerebras_key1", "cerebras_key2"]
    end
    
    @testset "Environment initialization" begin
        # Save original env
        original_openai = get(ENV, "OPENAI_API_KEY", "")
        original_openai_2 = get(ENV, "OPENAI_API_KEY_2", "")
        original_openai_3 = get(ENV, "OPENAI_API_KEY_3", "")
        
        try
            ENV["OPENAI_API_KEY"] = "test_openai_key_1"
            ENV["OPENAI_API_KEY_2"] = "test_openai_key_2"
            # Remove the 3rd key to create a gap, stopping collection at our 2 test keys
            haskey(ENV, "OPENAI_API_KEY_3") && delete!(ENV, "OPENAI_API_KEY_3")
            
            manager = EasyContext.APIKeyManager()
            EasyContext.initialize_from_env!(manager)
            
            @test !isempty(manager.provider_to_api_keys)
            @test haskey(manager.provider_to_api_keys, "openai")
            @test length(manager.provider_to_api_keys["openai"]) == 2
            @test manager.provider_to_api_keys["openai"][1].key == "test_openai_key_1"
            @test manager.provider_to_api_keys["openai"][2].key == "test_openai_key_2"
            
        finally
            # Restore environment
            if isempty(original_openai)
                haskey(ENV, "OPENAI_API_KEY") && delete!(ENV, "OPENAI_API_KEY")
            else
                ENV["OPENAI_API_KEY"] = original_openai
            end
            if isempty(original_openai_2)
                haskey(ENV, "OPENAI_API_KEY_2") && delete!(ENV, "OPENAI_API_KEY_2")
            else
                ENV["OPENAI_API_KEY_2"] = original_openai_2
            end
            if !isempty(original_openai_3)
                ENV["OPENAI_API_KEY_3"] = original_openai_3
            end
        end
    end
    
    @testset "collect_env_keys functionality" begin
        # Save original env
        original_test = get(ENV, "TEST_API_KEY", "")
        original_test_2 = get(ENV, "TEST_API_KEY_2", "")
        original_test_3 = get(ENV, "TEST_API_KEY_3", "")
        
        try
            ENV["TEST_API_KEY"] = "key1"
            ENV["TEST_API_KEY_2"] = "key2"
            ENV["TEST_API_KEY_3"] = "key3"
            
            keys = EasyContext.collect_env_keys("TEST_API_KEY")
            @test keys == ["key1", "key2", "key3"]
            
            # Test with missing middle key
            delete!(ENV, "TEST_API_KEY_2")
            keys = EasyContext.collect_env_keys("TEST_API_KEY")
            @test keys == ["key1"]  # Should stop at first missing numbered key
            
        finally
            # Restore environment
            for (env_var, original) in [("TEST_API_KEY", original_test), ("TEST_API_KEY_2", original_test_2), ("TEST_API_KEY_3", original_test_3)]
                if isempty(original)
                    haskey(ENV, env_var) && delete!(ENV, env_var)
                else
                    ENV[env_var] = original
                end
            end
        end
    end
    
    @testset "Global manager usage" begin
        # Test that global manager works
        original_state = copy(EasyContext.GLOBAL_API_KEY_MANAGER.provider_to_api_keys)
        try
            # Reset global manager for test
            empty!(EasyContext.GLOBAL_API_KEY_MANAGER.provider_to_api_keys)
            
            # Should initialize from environment automatically
            api_key = EasyContext.get_api_key_for_model("openai:openai/gpt-3.5-turbo", "test_request", "hello")
            # Should have initialized (might be empty if no env keys, but structure should exist)
            @test EasyContext.GLOBAL_API_KEY_MANAGER.provider_to_api_keys isa Dict
            
        finally
            # Restore global manager state
            EasyContext.GLOBAL_API_KEY_MANAGER.provider_to_api_keys = original_state
        end
    end
    
    @testset "find_api_key_for_request edge cases" begin
        manager = EasyContext.APIKeyManager()
        
        # Test with no keys for provider
        result = EasyContext.find_api_key_for_request(manager, "openai", nothing, 100)
        @test isnothing(result)
        
        # Test with empty key list
        manager.provider_to_api_keys["openai"] = EasyContext.StringApiKey[]
        result = EasyContext.find_api_key_for_request(manager, "openai", nothing, 100)
        @test isnothing(result)
        
        # Test expired affinity
        EasyContext.add_api_keys!(manager, "openai", ["key1"])
        manager.request_affinity["old_request"] = ("key1", time() - 400.0)  # Older than affinity_window
        result = EasyContext.find_api_key_for_request(manager, "openai", "old_request", 100)
        @test !isnothing(result)
        @test result.key == "key1"  # Should still get the key, just not through affinity
    end
end