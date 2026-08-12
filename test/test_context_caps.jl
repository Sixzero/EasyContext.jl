using Test
using EasyContext

@testset "context caps" begin
    effective(model; context_limit=0) = EasyContext.get_effective_limit(
        EasyContext.TokenBasedCutter(; model, context_limit)
    )

    # All providers cap at 200K: quality/cost cap, and keeps the 80% compaction
    # threshold (160K) aligned with the frontend indicator's 200K standard cap.
    @test effective("openai:openai/gpt-5.4") == 200_000
    @test effective("gpt5") == 200_000
    @test effective("anthropic:anthropic/claude-opus-4.8") == 200_000
    @test effective("claude") == 200_000
    @test effective("claude(high)") == 200_000
    @test effective("google-ai-studio:google/gemini-2.5-pro") == 200_000
    @test effective("gemf") == 200_000
    @test effective("gemf(high)") == 200_000

    @test effective(""; context_limit=123_000) == 123_000
    @test effective("") == 0
end
