using Test
using EasyContext
using PromptingTools
using RAGTools
using OpenRouter: ModelConfig
using EasyContext: get_model_name, is_openai_reasoning_model, is_mistral_model, is_claude_model, 
                   get_api_kwargs_for_model, apply_stop_sequences, aigenerate_with_config
using PromptingTools: AnthropicSchema

@testset "ModelConfig Tests" begin
    
    @testset "ModelConfig Construction" begin
        # Test basic construction with new structure
        config = ModelConfig(slug="test-model")
        @test config.slug == "test-model"
        @test config.schema === nothing
        @test config.kwargs == NamedTuple()
        
        # Test construction with all fields
        config = ModelConfig(
            slug="anthropic:claude-3",
            schema=AnthropicSchema(),
            kwargs=(; temperature=0.7, max_tokens=4000)
        )
        @test config.slug == "anthropic:claude-3"
        @test config.schema isa AnthropicSchema
        @test config.kwargs.temperature == 0.7
        @test config.kwargs.max_tokens == 4000
    end
    
    @testset "Model Type Detection Logic" begin
        # Test OpenAI reasoning models - these should bypass normal API kwargs
        @test is_openai_reasoning_model("o3") == true
        @test is_openai_reasoning_model("o3m") == true
        @test is_openai_reasoning_model("o4m") == true
        @test is_openai_reasoning_model("gpt-5") == true
        @test is_openai_reasoning_model("gpt-5-turbo") == true
        @test is_openai_reasoning_model("gpt-5-preview") == true
        @test is_openai_reasoning_model("gpt-4") == false
        @test is_openai_reasoning_model("claude") == false

        # Test Mistral models - these should have top_p removed
        @test is_mistral_model("mistral-large") == true
        @test is_mistral_model("mistral-7b") == true
        @test is_mistral_model("mistral-instruct") == true
        @test is_mistral_model("gpt-4") == false
        @test is_mistral_model("claude") == false

        # Test Claude models - these should get max_tokens=16000
        @test is_claude_model("claude") == true
        @test is_claude_model("claude-3") == true
        @test is_claude_model("claude-3-sonnet") == true
        @test is_claude_model("gpt-4") == false
        @test is_claude_model("mistral-large") == false
    end
    
    @testset "API Kwargs Transformation - String Models" begin
        base_kwargs = (; temperature=0.7, top_p=0.9, max_tokens=1000)
        
        # OpenAI reasoning models should return empty kwargs (bypass everything)
        @test get_api_kwargs_for_model("o3", base_kwargs) == NamedTuple()
        @test get_api_kwargs_for_model("o3m", base_kwargs) == NamedTuple()
        @test get_api_kwargs_for_model("gpt-5", base_kwargs) == NamedTuple()
        @test get_api_kwargs_for_model("gpt-5-turbo", base_kwargs) == NamedTuple()
        
        # Claude models should override max_tokens to 16000
        result = get_api_kwargs_for_model("claude", base_kwargs)
        @test result.temperature == 0.7
        @test result.top_p == 0.9
        @test result.max_tokens == 16000  # Should override original 1000
        
        # Mistral models should remove top_p but keep other params
        result = get_api_kwargs_for_model("mistral-large", base_kwargs)
        @test result.temperature == 0.7
        @test result.max_tokens == 1000
        @test !haskey(result, :top_p)  # Should be removed
        
        # Regular models should pass through unchanged
        @test get_api_kwargs_for_model("gpt-4", base_kwargs) == base_kwargs
        @test get_api_kwargs_for_model("unknown-model", base_kwargs) == base_kwargs
    end
    
    @testset "API Kwargs with ModelConfig Defaults" begin
        # Test that ModelConfig kwargs are merged but base_kwargs take precedence
        config = ModelConfig(
            slug="anthropic:claude-3",
            kwargs=(; max_tokens=8000, temperature=0.5, top_k=10)
        )
        
        base_kwargs = (; temperature=0.7, top_p=0.9)
        result = get_api_kwargs_for_model(config, base_kwargs)
        
        # base_kwargs should override config kwargs
        @test result.temperature == 0.7  # from base_kwargs, not config's 0.5
        @test result.top_p == 0.9  # from base_kwargs
        @test result.top_k == 10  # from config (not in base_kwargs)
        @test result.max_tokens == 16000  # Claude-specific override
        
        # Test Mistral with config kwargs
        mistral_config = ModelConfig(
            slug="mistral:mistral-large",
            kwargs=(; temperature=0.3, top_p=0.8, max_tokens=2000)
        )
        
        result = get_api_kwargs_for_model(mistral_config, base_kwargs)
        @test result.temperature == 0.7  # base_kwargs override
        @test result.max_tokens == 2000  # from config
        @test !haskey(result, :top_p)  # Removed for Mistral (even though in both config and base)
    end
    
    @testset "Stop Sequences Handling" begin
        base_kwargs = (; temperature=0.7, max_tokens=1000)
        stop_seqs = ["STOP", "END"]
        
        # Empty stop sequences should return unchanged kwargs
        @test apply_stop_sequences("gpt-4", base_kwargs, String[]) == base_kwargs
        
        # Gemini should ignore stop sequences completely
        result = apply_stop_sequences("gemini-pro", base_kwargs, stop_seqs)
        @test result == base_kwargs
        @test !haskey(result, :stop)
        @test !haskey(result, :stop_sequences)
        
        # OpenAI reasoning models should ignore stop sequences (including GPT-5)
        @test apply_stop_sequences("o3", base_kwargs, stop_seqs) == base_kwargs
        @test apply_stop_sequences("gpt-5", base_kwargs, stop_seqs) == base_kwargs
        @test apply_stop_sequences("gpt-5-turbo", base_kwargs, stop_seqs) == base_kwargs
        
        # Claude models should use :stop_sequences parameter
        result = apply_stop_sequences("claude", base_kwargs, stop_seqs)
        @test result.temperature == 0.7
        @test result.max_tokens == 1000
        @test result.stop_sequences == stop_seqs
        @test !haskey(result, :stop)
        
        # OpenAI models should use :stop parameter
        result = apply_stop_sequences("gpt-4", base_kwargs, stop_seqs)
        @test result.temperature == 0.7
        @test result.max_tokens == 1000
        @test result.stop == stop_seqs
        @test !haskey(result, :stop_sequences)
        
        # Test with ModelConfig
        claude_config = ModelConfig(slug="anthropic:claude-3")
        result = apply_stop_sequences(claude_config, base_kwargs, stop_seqs)
        @test result.stop_sequences == stop_seqs
        @test !haskey(result, :stop)

        # Grok models should ignore stop sequences (exact and startswith)
        @test apply_stop_sequences("grok-code-fast-1", base_kwargs, stop_seqs) == base_kwargs
        result = apply_stop_sequences("grok-2", base_kwargs, stop_seqs)
        @test result == base_kwargs
        @test !haskey(result, :stop)
        @test !haskey(result, :stop_sequences)
    end
    
    @testset "Edge Cases and Complex Scenarios" begin
        # Test empty kwargs with model-specific rules
        empty_kwargs = NamedTuple()
        
        # Claude should still add max_tokens even with empty input
        result = get_api_kwargs_for_model("claude", empty_kwargs)
        @test result.max_tokens == 16000
        @test length(result) == 1
        
        # Mistral with only top_p should remove it completely
        only_top_p = (; top_p=0.9)
        result = get_api_kwargs_for_model("mistral-large", only_top_p)
        @test result == NamedTuple()  # Should be empty after removing top_p
        
        # Test ModelConfig with reasoning model (should override everything)
        reasoning_config = ModelConfig(
            slug="openai:o3",
            kwargs=(; temperature=0.5, max_tokens=4000, top_p=0.8)
        )
        
        rich_kwargs = (; temperature=0.7, top_p=0.9, max_tokens=2000, custom_param=42)
        result = get_api_kwargs_for_model(reasoning_config, rich_kwargs)
        @test result == NamedTuple()  # Should ignore everything for reasoning models
        
        # Test GPT-5 as reasoning model (should also override everything)
        gpt5_config = ModelConfig(
            slug="openai:gpt-5",
            kwargs=(; temperature=0.5, max_tokens=4000, top_p=0.8)
        )
        
        result = get_api_kwargs_for_model(gpt5_config, rich_kwargs)
        @test result == NamedTuple()  # Should ignore everything for GPT-5 models
    end
    
    @testset "Model Name Extraction" begin
        # Test that get_model_name works correctly for both types
        @test get_model_name("gpt-4") == "gpt-4"
        
        config = ModelConfig(slug="anthropic:claude-3")
        @test get_model_name(config) == "anthropic:claude-3"
        
        # This enables polymorphic usage in other functions
        models = [
            "gpt-4",
            ModelConfig(slug="anthropic:claude-3"),
            ModelConfig(slug="mistral:mistral-large")
        ]
        
        names = [get_model_name(m) for m in models]
        @test names == ["gpt-4", "anthropic:claude-3", "mistral:mistral-large"]
    end
    
    @testset "Integration: Full Workflow" begin
        # Test realistic scenario: Mistral model with config kwargs and stop sequences
        config = ModelConfig(
            slug="mistral:mistral-large",
            kwargs=(; temperature=0.3, top_p=0.8, max_tokens=2000, custom_param="test")
        )
        
        # User provides some overrides
        user_kwargs = (; temperature=0.7, top_p=0.9, extra_param=42)
        stop_seqs = ["STOP", "END"]
        
        # Step 1: Apply model-specific kwargs
        api_kwargs = get_api_kwargs_for_model(config, user_kwargs)
        @test api_kwargs.temperature == 0.7  # User override
        @test api_kwargs.max_tokens == 2000  # From config
        @test api_kwargs.custom_param == "test"  # From config
        @test api_kwargs.extra_param == 42  # From user
        @test !haskey(api_kwargs, :top_p)  # Removed for Mistral
        
        # Step 2: Apply stop sequences
        final_kwargs = apply_stop_sequences(config, api_kwargs, stop_seqs)
        @test final_kwargs.stop == stop_seqs  # Mistral uses :stop
        @test final_kwargs.temperature == 0.7
        @test final_kwargs.max_tokens == 2000
        @test final_kwargs.custom_param == "test"
        @test final_kwargs.extra_param == 42
        @test !haskey(final_kwargs, :stop_sequences)
        
        # Test that reasoning models bypass everything (including GPT-5)
        reasoning_config = ModelConfig(
            slug="openai:o3",
            kwargs=(; temperature=0.5, max_tokens=4000)
        )
        
        gpt5_config = ModelConfig(
            slug="openai:gpt-5-preview",
            kwargs=(; temperature=0.5, max_tokens=4000)
        )
        
        user_kwargs = (; temperature=0.7, top_p=0.9, max_tokens=2000, custom_param=42)
        stop_seqs = ["STOP", "END"]
        
        for cfg in [reasoning_config, gpt5_config]
            api_kwargs = get_api_kwargs_for_model(cfg, user_kwargs)
            final_kwargs = apply_stop_sequences(cfg, api_kwargs, stop_seqs)
            @test final_kwargs == NamedTuple()  # Should be completely empty
        end
    end
end