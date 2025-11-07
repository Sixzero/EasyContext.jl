using Test
using EasyContext
using PromptingTools
using PromptingTools: OpenAISchema, AbstractPromptSchema, CerebrasOpenAISchema

@testset "API Key Manager Tests" begin
    
    @testset "StringApiKey basic functionality" begin
        api_key = EasyContext.StringApiKey("test_key_123")
        @test api_key.key == "test_key_123"
        @test api_key.schema_name == "OpenAISchema"
        @test LLMRateLimiters.current_usage(api_key.rate_limiter) == 0
        @test LLMRateLimiters.can_add_tokens(api_key.rate_limiter, 1000)
    end
    
    @testset "APIKeyManager initialization" begin
        manager = EasyContext.APIKeyManager()
        @test manager.affinity_window == 300.0
        @test isempty(manager.schema_to_api_keys)
        @test isempty(manager.request_affinity)
    end
    
    @testset "get_model_schema functionality" begin
        # Test with string model
        schema = EasyContext.get_model_schema("gpt-3.5-turbo")
        @test schema isa AbstractPromptSchema
        
        # Test with ModelConfig
        config = ModelConfig(name="test", schema=CerebrasOpenAISchema())
        schema = EasyContext.get_model_schema(config)
        @test schema isa CerebrasOpenAISchema
        
        # Test with ModelConfig without schema
        config_no_schema = ModelConfig(name="test")
        schema = EasyContext.get_model_schema(config_no_schema)
        @test schema isa OpenAISchema
    end
    
    @testset "API key registration" begin
        manager = EasyContext.APIKeyManager()
        
        # Add API keys
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1", "key2", "key3"])
        @test length(manager.schema_to_api_keys[OpenAISchema]) == 3
        @test manager.schema_to_api_keys[OpenAISchema][1].key == "key1"
        @test manager.schema_to_api_keys[OpenAISchema][2].key == "key2"
        @test manager.schema_to_api_keys[OpenAISchema][3].key == "key3"
    end
    
    @testset "API key selection without request_id" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1", "key2"])
        
        # Should return a key (lowest usage initially)
        api_key = EasyContext.get_api_key_for_model("gpt-3.5-turbo", nothing, "test prompt"; manager=manager)
        @test api_key in ["key1", "key2"]
    end
    
    @testset "API key selection with request_id routing" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1", "key2"])
        
        # First request should get a key
        api_key1 = EasyContext.get_api_key_for_model("gpt-3.5-turbo", "request_123", "test prompt"; manager=manager)
        @test api_key1 in ["key1", "key2"]
        
        # Second request with same ID should get same key (within affinity window)
        api_key2 = EasyContext.get_api_key_for_model("gpt-3.5-turbo", "request_123", "another prompt"; manager=manager)
        @test api_key2 == api_key1
        
        # Different request ID might get different key
        api_key3 = EasyContext.get_api_key_for_model("gpt-3.5-turbo", "request_456", "different prompt"; manager=manager)
        @test api_key3 in ["key1", "key2"]
    end

    @testset "Echo model request_id behavior" begin
        manager = EasyContext.APIKeyManager()
        
        # Get the actual schema type for echo model
        echo_schema = EasyContext.get_model_schema("echo")
        echo_schema_type = typeof(echo_schema)
        
        # Add keys for the correct schema type
        EasyContext.add_api_keys!(manager, echo_schema_type, ["echo_key1", "echo_key2", "echo_key3"])
        
        # Debug: Check that keys are properly stored
        @test haskey(manager.schema_to_api_keys, echo_schema_type)
        @test length(manager.schema_to_api_keys[echo_schema_type]) == 3
        
        # Test sticky routing with echo model
        api_key1 = EasyContext.get_api_key_for_model("echo", "sticky_request", "test"; manager=manager)
        @test !isnothing(api_key1)
        @test api_key1 in ["echo_key1", "echo_key2", "echo_key3"]
        
        api_key2 = EasyContext.get_api_key_for_model("echo", "sticky_request", "test"; manager=manager)
        api_key3 = EasyContext.get_api_key_for_model("echo", "sticky_request", "test"; manager=manager)
        @test api_key1 == api_key2 == api_key3  # Same request_id should always return same key
        
        # Test without request_id - should potentially vary
        keys_without_id = String[]
        for i in 1:10
            key = EasyContext.get_api_key_for_model("echo", nothing, "test $i"; manager=manager)
            if !isnothing(key)
                push!(keys_without_id, key)
            end
        end
        @test all(k -> k in ["echo_key1", "echo_key2", "echo_key3"], keys_without_id)
        @test !isempty(keys_without_id)  # Should have gotten at least some keys
        
        # Test different request_ids get potentially different keys
        key_a = EasyContext.get_api_key_for_model("echo", "request_a", "test"; manager=manager)
        key_b = EasyContext.get_api_key_for_model("echo", "request_b", "test"; manager=manager)
        key_c = EasyContext.get_api_key_for_model("echo", "request_c", "test"; manager=manager)
        @test !isnothing(key_a) && !isnothing(key_b) && !isnothing(key_c)
        @test all(k -> k in ["echo_key1", "echo_key2", "echo_key3"], [key_a, key_b, key_c])
        
        # But same request_ids should be consistent
        @test EasyContext.get_api_key_for_model("echo", "request_a", "different prompt"; manager=manager) == key_a
        @test EasyContext.get_api_key_for_model("echo", "request_b", "different prompt"; manager=manager) == key_b
        @test EasyContext.get_api_key_for_model("echo", "request_c", "different prompt"; manager=manager) == key_c
    end

    @testset "Rate limiting behavior" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1", "key2"], 10)  # Very low limit for testing
        
        # Use up tokens on both keys
        for i in 1:8
            EasyContext.get_api_key_for_model("gpt-3.5-turbo", "request_$i", "test prompt with many tokens"; manager=manager)
        end
        
        # Should still work (load balancing between keys)
        api_key = EasyContext.get_api_key_for_model("gpt-3.5-turbo", "request_new", "test prompt"; manager=manager)
        @test api_key in ["key1", "key2"]
    end
    
    @testset "Usage tracking" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1"])
        
        # Get the key object to check usage
        key_obj = manager.schema_to_api_keys[OpenAISchema][1]
        initial_usage = LLMRateLimiters.current_usage(key_obj.rate_limiter)
        
        # Make a request
        EasyContext.get_api_key_for_model("gpt-3.5-turbo", "test_request", "hello world test"; manager=manager)
        
        # Usage should have increased
        new_usage = LLMRateLimiters.current_usage(key_obj.rate_limiter)
        @test new_usage > initial_usage
    end
    
    @testset "ModelConfig integration" begin
        manager = EasyContext.APIKeyManager()
        EasyContext.add_api_keys!(manager, CerebrasOpenAISchema, ["cerebras_key1", "cerebras_key2"])
        
        model_config = ModelConfig(
            name = "gpt-oss-120b",
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
            
            @test !isempty(manager.schema_to_api_keys)
            @test haskey(manager.schema_to_api_keys, OpenAISchema)
            @test length(manager.schema_to_api_keys[OpenAISchema]) == 2
            @test manager.schema_to_api_keys[OpenAISchema][1].key == "test_openai_key_1"
            @test manager.schema_to_api_keys[OpenAISchema][2].key == "test_openai_key_2"
            
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
        original_state = copy(EasyContext.GLOBAL_API_KEY_MANAGER.schema_to_api_keys)
        try
            # Reset global manager for test
            empty!(EasyContext.GLOBAL_API_KEY_MANAGER.schema_to_api_keys)
            
            # Should initialize from environment automatically
            api_key = EasyContext.get_api_key_for_model("gpt-3.5-turbo", "test_request", "hello")
            # Should have initialized (might be empty if no env keys, but structure should exist)
            @test EasyContext.GLOBAL_API_KEY_MANAGER.schema_to_api_keys isa Dict
            
        finally
            # Restore global manager state
            EasyContext.GLOBAL_API_KEY_MANAGER.schema_to_api_keys = original_state
        end
    end
    
    @testset "find_api_key_for_request edge cases" begin
        manager = EasyContext.APIKeyManager()
        
        # Test with no keys for schema
        result = EasyContext.find_api_key_for_request(manager, OpenAISchema, nothing, 100)
        @test isnothing(result)
        
        # Test with empty key list
        manager.schema_to_api_keys[OpenAISchema] = EasyContext.StringApiKey[]
        result = EasyContext.find_api_key_for_request(manager, OpenAISchema, nothing, 100)
        @test isnothing(result)
        
        # Test expired affinity
        EasyContext.add_api_keys!(manager, OpenAISchema, ["key1"])
        manager.request_affinity["old_request"] = ("key1", time() - 400.0)  # Older than affinity_window
        result = EasyContext.find_api_key_for_request(manager, OpenAISchema, "old_request", 100)
        @test !isnothing(result)
        @test result.key == "key1"  # Should still get the key, just not through affinity
    end
end