using Test
using EasyContext
using EasyContext: TokenBasedCutter, record_real_usage!, context_model, current_context_tokens,
                   estimate_conversation_tokens, create_user_message

# Build a conversation whose chars/2 estimate is roughly `est_tokens`.
struct FakeConv
    messages::Vector{Any}
end
fake_conv(est_tokens::Int) = FakeConv([create_user_message("x"^(2 * est_tokens))])

@testset "TokenBasedCutter context model" begin
    limit = 200_000

    @testset "no anchor → raw estimate" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        conv = fake_conv(10_000)
        @test current_context_tokens(cutter, conv) == estimate_conversation_tokens(cutter, conv)
    end

    @testset "single anchor: overhead absorbed, exact at anchor, delta at 0.5" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        conv = fake_conv(2_000)
        # Real API usage 30K (system prompt/tools/skills) vs conversation estimate ~2K.
        record_real_usage!(cutter, conv, 30_000)
        @test current_context_tokens(cutter, conv) == 30_000     # exact at the anchor

        # Conversation grows to est 16K: must NOT extrapolate proportionally (old bug
        # read this as 15×16K = 240K and fired compaction); only the delta is scaled.
        grown = fake_conv(16_000)
        cur = current_context_tokens(cutter, grown)
        @test 30_000 < cur < 45_000
    end

    @testset "single anchor with real < 0.5·estimate stays exact at anchor" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        conv = fake_conv(100_000)
        record_real_usage!(cutter, conv, 30_000)   # slope capped to real/est, overhead 0
        overhead, slope = context_model(cutter)
        @test overhead >= 0
        @test current_context_tokens(cutter, conv) == 30_000
    end

    @testset "near-identical anchors don't fit a runaway slope" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        record_real_usage!(cutter, fake_conv(5_000), 40_000)
        # +2K real tokens (e.g. image) but only +10 estimate tokens: old code fit slope 8+.
        record_real_usage!(cutter, fake_conv(5_010), 42_000)
        _, slope = context_model(cutter)
        @test slope <= 2.5
        cur = current_context_tokens(cutter, fake_conv(20_000))
        @test cur < 60_000                          # old model said 167K here
    end

    @testset "gradual growth still reaches a two-anchor fit" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        # overhead 25K, true slope 1.0; grow 100 est-tokens per turn.
        for est in 1_000:100:2_000
            record_real_usage!(cutter, fake_conv(est), 25_000 + est)
        end
        overhead, slope = context_model(cutter)
        @test 0.8 <= slope <= 1.2                   # fitted, not stuck at default 0.5
        @test 20_000 <= overhead <= 30_000
    end

    @testset "well-separated anchors fit overhead + slope" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        record_real_usage!(cutter, fake_conv(40_000), 50_000)   # 26K + 0.6·40K
        record_real_usage!(cutter, fake_conv(90_000), 80_000)   # 26K + 0.6·90K
        overhead, slope = context_model(cutter)
        @test isapprox(slope, 0.6; atol=0.01)
        @test isapprox(overhead, 26_000; atol=500)
    end

    @testset "negative-intercept fit is rejected, model stays exact at anchor" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        record_real_usage!(cutter, fake_conv(1_000), 400)
        record_real_usage!(cutter, fake_conv(2_000), 1_000)     # slope 0.6, intercept −200
        overhead, slope = context_model(cutter)
        @test overhead >= 0
        @test current_context_tokens(cutter, fake_conv(2_000)) == 1_000
    end
end
