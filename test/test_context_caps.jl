using Test
using EasyContext

@testset "provider-specific context caps" begin
    effective(model; context_limit=0) = EasyContext.get_effective_limit(
        EasyContext.TokenBasedCutter(; model, context_limit)
    )

    @test effective("openai:openai/gpt-5.4") == 200_000
    @test effective("gpt5") == 200_000

    @test effective("anthropic:anthropic/claude-opus-4.8") == 250_000
    @test effective("claude") == 250_000
    @test effective("claude(high)") == 250_000
    @test effective("google-ai-studio:google/gemini-2.5-pro") == 250_000
    @test effective("gemf") == 250_000
    @test effective("gemf(high)") == 250_000

    @test effective(""; context_limit=123_000) == 123_000
    @test effective("") == 0
end
