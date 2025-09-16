using Test
using EasyContext
using PromptingTools
using HTTP

@testset "API Key Rotation Tests" begin
    
    @testset "get_api_key_env_var" begin
        @test EasyContext.get_api_key_env_var(PromptingTools.OpenAISchema) == "OPENAI_API_KEY"
        @test EasyContext.get_api_key_env_var(PromptingTools.CerebrasOpenAISchema) == "CEREBRAS_API_KEY"
        @test EasyContext.get_api_key_env_var(PromptingTools.MistralOpenAISchema) == "MISTRAL_API_KEY"
        @test EasyContext.get_api_key_env_var(PromptingTools.AnthropicSchema) == "ANTHROPIC_API_KEY"
        
        # Test unknown schema defaults to OPENAI_API_KEY
        struct UnknownSchema end
        @test EasyContext.get_api_key_env_var(UnknownSchema) == "OPENAI_API_KEY"
    end
    
    @testset "is_quota_exceeded_error" begin
        # Test HTTP 429 error
        http_error = HTTP.Exceptions.StatusError(429, "GET", "/test", HTTP.Response(429))
        @test EasyContext.is_quota_exceeded_error(http_error)
        
        # Test HTTP 500 error (should not be quota exceeded)
        http_error_500 = HTTP.Exceptions.StatusError(500, "GET", "/test", HTTP.Response(500))
        @test !EasyContext.is_quota_exceeded_error(http_error_500)
        
        # Test error with quota message
        quota_error = ErrorException("Rate limit exceeded")
        @test EasyContext.is_quota_exceeded_error(quota_error)
        
        # Test regular error
        regular_error = ErrorException("Connection failed")
        @test !EasyContext.is_quota_exceeded_error(regular_error)
    end
    
    @testset "ModelState with API key tracking" begin
        state = EasyContext.ModelState()
        @test state.current_api_key_index == 1
        @test state.failures == 0
        @test state.available == true
    end
    
    @testset "AIGenerateFallback with API key rotation" begin
        manager = EasyContext.AIGenerateFallback(models=["gpt-3.5-turbo"])
        @test manager.api_key_rotation == true
        
        # Test disabling API key rotation
        manager_no_rotation = EasyContext.AIGenerateFallback(models=["gpt-3.5-turbo"], api_key_rotation=false)
        @test manager_no_rotation.api_key_rotation == false
    end
    
    @testset "rotate_api_key! functionality" begin
        # Setup test environment
        original_key = get(ENV, "CEREBRAS_API_KEY", "")
        original_key_2 = get(ENV, "CEREBRAS_API_KEY_2", "")
        original_pt_key = isdefined(PromptingTools, :CEREBRAS_API_KEY) ? getproperty(PromptingTools, :CEREBRAS_API_KEY) : ""
        
        try
            # Set up test keys
            ENV["CEREBRAS_API_KEY"] = "test_key_1"
            ENV["CEREBRAS_API_KEY_2"] = "test_key_2"
            PromptingTools.CEREBRAS_API_KEY = "test_key_1"
            
            manager = EasyContext.AIGenerateFallback(models=["test-model"])
            state = EasyContext.ModelState()
            manager.states["test-model"] = state
            
            # Test successful rotation
            @test EasyContext.rotate_api_key!(manager, "test-model", PromptingTools.CerebrasOpenAISchema)
            @test state.current_api_key_index == 2
            @test PromptingTools.CEREBRAS_API_KEY == "test_key_2"
            @test ENV["CEREBRAS_API_KEY"] == "test_key_1"  # ENV unchanged
            
            # Test rotation when no next key exists - should reset to index 1
            @test EasyContext.rotate_api_key!(manager, "test-model", PromptingTools.CerebrasOpenAISchema)
            @test state.current_api_key_index == 1
            @test PromptingTools.CEREBRAS_API_KEY == "test_key_1"
            
            # Test with rotation disabled
            manager.api_key_rotation = false
            state.current_api_key_index = 1
            @test !EasyContext.rotate_api_key!(manager, "test-model", PromptingTools.CerebrasOpenAISchema)
            @test state.current_api_key_index == 1  # Should remain unchanged
            
        finally
            # Restore original environment
            if isempty(original_key)
                delete!(ENV, "CEREBRAS_API_KEY")
            else
                ENV["CEREBRAS_API_KEY"] = original_key
            end
            if isempty(original_key_2)
                delete!(ENV, "CEREBRAS_API_KEY_2")
            else
                ENV["CEREBRAS_API_KEY_2"] = original_key_2
            end
            PromptingTools.CEREBRAS_API_KEY = original_pt_key
        end
    end
    
    @testset "Integration test with Cerebras (rate limit scenario)" begin
        # This test only works if you have rate-limited Cerebras API keys
        # Skip if no Cerebras keys are available
        if !haskey(ENV, "CEREBRAS_API_KEY") || isempty(ENV["CEREBRAS_API_KEY"])
            @test_skip "Skipping Cerebras integration test - no API key available"
            return
        end
        
        model_config = ModelConfig(
            name = "gpt-oss-120b",
            schema = PromptingTools.CerebrasOpenAISchema(),
            cost_of_token_prompt = 0.25e-6,
            cost_of_token_generation = 0.69e-6,
            extras=(;context_length=131_000),
        )
        
        manager = EasyContext.AIGenerateFallback(models=[model_config])
        
        # Test that the manager can handle the model
        @test length(manager.models) == 1
        
        # If we have multiple API keys set up, we can test rotation
        if haskey(ENV, "CEREBRAS_API_KEY_2")
            # This would test actual API key rotation in a real scenario
            # For now, just verify the setup works
            state = get!(manager.states, "gpt-oss-120b", EasyContext.ModelState())
            @test state.current_api_key_index == 1
            
            # Simulate a quota exceeded error and rotation
            if EasyContext.rotate_api_key!(manager, "gpt-oss-120b", PromptingTools.CerebrasOpenAISchema)
                @test state.current_api_key_index == 2
                @test PromptingTools.CEREBRAS_API_KEY == ENV["CEREBRAS_API_KEY_2"]
            end
        else
            @test_skip "Skipping API key rotation test - only one Cerebras API key available"
        end
    end
end
#%%


model_config = ModelConfig(
    name = "gpt-oss-120b",
    schema = PromptingTools.CerebrasOpenAISchema(),
    cost_of_token_prompt = 0.25e-6,
    cost_of_token_generation = 0.69e-6,
    extras=(;context_length=131_000),
)

PromptingTools.CEREBRAS_API_KEY = "csk-cdkv9dmmfc3xftkmfjkm5y5r2843tfnyvnmw9xt86rfynt2h"
# aigenerate_with_config(model_config, "Say hi")
# export CEREBRAS_API_KEY_2=csk-9e33jf6622emdwf2vr658cdev34kdf9jyr4vdxkpk8wvm5cc
manager = EasyContext.AIGenerateFallback(models=[model_config])
@show PromptingTools.CEREBRAS_API_KEY
result = EasyContext.try_generate(manager, "Say hello in one word")
@show PromptingTools.CEREBRAS_API_KEY