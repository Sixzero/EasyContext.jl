using Test
using EasyContext
using PromptingTools
using RAGTools
using OpenRouter: ModelConfig
using EasyContext: get_model_name, is_openai_reasoning_model, is_mistral_model, is_claude_model, 
                   get_api_kwargs_for_model, apply_stop_sequences, aigenerate_with_config,
                   _is_transient_error
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

        # Test Claude model detection
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
        
        # Claude models pass through unchanged (max_tokens default handled by OpenRouter.jl)
        result = get_api_kwargs_for_model("claude", base_kwargs)
        @test result.temperature == 0.7
        @test result.top_p == 0.9
        @test result.max_tokens == 1000
        
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
        @test result.max_tokens == 8000  # from config; no Claude override anymore
        
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
    
    @testset "Transient Error Classification" begin
        # Streaming connection reset (Go/TCP human-readable form) must be retryable
        @test _is_transient_error(
            "Error detected in the streaming response: Type: api_error, Message: read tcp [2a01:4f9:6a:470e::2]:55874->[2607:6bc0::10]:443: read: connection reset by peer")
        @test _is_transient_error("ECONNRESET")
        @test _is_transient_error("connection refused")
        @test _is_transient_error("connection closed")
        @test _is_transient_error("HTTP status 503 Service Unavailable")
        @test _is_transient_error("rate limit exceeded, too many requests")
        # Client/permanent errors must NOT be retried
        @test !_is_transient_error("status 400 bad request")
        @test !_is_transient_error("invalid api key")

        # CLIProxyAPI pool exhaustion stays retryable like any other 429 — the proxy
        # rotates credentials, so an attempt can land on a live one.
        @test _is_transient_error(
            """API Error (503): auth_unavailable: no auth available; last upstream error: {"error":{"type":"usage_limit_reached","message":"The usage limit has been reached","plan_type":"prolite","resets_at":1787197022}} (status 429); retry in 42h8m45s (providers=codex, model=gpt-5.6-sol(high))""")
        @test _is_transient_error(
            """API Error (429): {"error":{"code":"model_cooldown","message":"All credentials for model claude-fable-5(medium) are cooling down","reset_seconds":151725}}""")
    end

    @testset "Pool Exhaustion Messaging" begin
        using EasyContext: parse_retry_after_seconds, format_duration, _is_pool_exhausted_error

        # Both upstream shapes + our gateway's sanitized relay are recognised, so the
        # raw blob (it carries OUR account internals) never reaches the user.
        @test _is_pool_exhausted_error("api error (503): auth_unavailable: no auth available")
        @test _is_pool_exhausted_error("""{"code":"model_cooldown","reset_seconds":151725}""")
        @test _is_pool_exhausted_error("all credentials for model claude-fable-5(medium) are cooling down")
        @test _is_pool_exhausted_error("model gpt-5.6-sol(high) is temporarily at capacity. retry after 151725s.")
        @test !_is_pool_exhausted_error("api error (429): rate limit exceeded for your account")

        # "retry in X" cooldown parsing
        @test parse_retry_after_seconds("(status 429); retry in 42h8m45s (providers=codex)") == 42*3600 + 8*60 + 45
        @test parse_retry_after_seconds("retry in 30m") == 1800
        @test parse_retry_after_seconds("retry in 12s") == 12
        @test parse_retry_after_seconds("no cooldown mentioned") === nothing
        # model_cooldown shape + gateway relay
        @test parse_retry_after_seconds("""{"code":"model_cooldown","reset_seconds":151725}""") == 151725
        @test parse_retry_after_seconds("""{"reset_time":"1h2m3s"}""") == 3723
        @test parse_retry_after_seconds("Retry after 3723s.") == 3723
        @test format_duration(151725) == "42h8m"
        @test format_duration(250) == "4m10s"
    end

    @testset "Stream Stall Cooldown" begin
        using EasyContext: _is_stall_error, maybe_mark_stalled!, is_model_available,
            GLOBAL_MODEL_STATES, STALL_COOLDOWN
        using OpenRouter: StreamIdleTimeoutError

        @test _is_stall_error(StreamIdleTimeoutError(60.0))
        @test _is_stall_error("StreamIdleTimeoutError: no data received for 60.0s (stream stalled)")
        @test !_is_stall_error("HTTP status 503 Service Unavailable")

        test_model = "openai:openai/test-stall-model"
        try
            @test maybe_mark_stalled!(test_model, StreamIdleTimeoutError(60.0))
            @test !is_model_available(test_model)
            @test GLOBAL_MODEL_STATES[test_model].recovery_time == STALL_COOLDOWN
            @test !maybe_mark_stalled!("other-stall-model", ErrorException("timeout"))

            # A short stall cooldown must not shorten a stronger cooldown
            # already in force on the same model
            EasyContext.mark_model_unavailable!(test_model, "longer cooldown"; recovery_time=7200)
            @test GLOBAL_MODEL_STATES[test_model].recovery_time == 7200
            @test maybe_mark_stalled!(test_model, StreamIdleTimeoutError(60.0))  # detected…
            @test GLOBAL_MODEL_STATES[test_model].recovery_time == 7200          # …but not weakened
        finally
            delete!(GLOBAL_MODEL_STATES, test_model)
        end

        # _aigen_with_retry: pre-first-chunk stall RETRIES (idempotent — zero
        # bytes received), and only marks the cooldown after the final attempt.
        # Mid-stream stall (chunks already received) fails fast, no retry, no
        # cooldown.
        using EasyContext: _aigen_with_retry
        using OpenRouter: HttpStreamHooks, StreamChunk
        pre_model, mid_model = "openai:openai/test-prestall", "openai:openai/test-midstall"
        try
            # Retryable: second attempt succeeds after a pre-first-chunk stall.
            calls = Ref(0)
            result = _aigen_with_retry(; model_name=pre_model) do
                calls[] += 1
                calls[] == 1 ? throw(StreamIdleTimeoutError(30.0)) : :ok
            end
            @test result == :ok && calls[] == 2
            @test is_model_available(pre_model)  # no cooldown on recovered stall

            # All attempts stall → rethrown + cooldown marked.
            @test_throws StreamIdleTimeoutError _aigen_with_retry(
                () -> throw(StreamIdleTimeoutError(30.0)); model_name=pre_model, max_retries=1)
            @test !is_model_available(pre_model)

            # Mid-stream stall: no retry, no cooldown.
            cb = HttpStreamHooks()
            push!(cb, StreamChunk(data="data"))
            mid_calls = Ref(0)
            @test_throws StreamIdleTimeoutError _aigen_with_retry(
                () -> (mid_calls[] += 1; throw(StreamIdleTimeoutError(30.0)));
                model_name=mid_model, streamcallback=cb)
            @test mid_calls[] == 1
            @test is_model_available(mid_model)
        finally
            delete!(GLOBAL_MODEL_STATES, pre_model)
            delete!(GLOBAL_MODEL_STATES, mid_model)
        end
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