using Test
using EasyContext
using EasyContext: TokenBasedCutter, record_real_usage!, current_context_tokens,
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

    @testset "exact at the anchor, only the delta is scaled" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        # Real API usage 30K (system prompt/tools/skills) vs conversation estimate ~2K.
        record_real_usage!(cutter, fake_conv(2_000), 30_000)
        @test current_context_tokens(cutter, fake_conv(2_000)) == 30_000
        # Grown to est 16K: +14K estimate → +7K real, never a proportional 15× blow-up.
        @test current_context_tokens(cutter, fake_conv(16_000)) == 37_000
        # Shrunk (a cut): the removed estimate drops out.
        @test current_context_tokens(cutter, fake_conv(1_000)) == 29_500
        @test current_context_tokens(cutter, fake_conv(0)) == 29_000
    end

    @testset "a cut never extrapolates below zero" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        # Real 170K on a 400K estimate (dense ASCII): slope caps at 170/400, not 0.5.
        record_real_usage!(cutter, fake_conv(400_000), 170_000)
        @test current_context_tokens(cutter, fake_conv(400_000)) == 170_000
        @test current_context_tokens(cutter, fake_conv(40_000)) == 17_000
        @test current_context_tokens(cutter, fake_conv(0)) == 0
    end

    @testset "an image-only jump between calls just moves the anchor" begin
        cutter = TokenBasedCutter(; context_limit=limit)
        record_real_usage!(cutter, fake_conv(5_000), 40_000)
        record_real_usage!(cutter, fake_conv(5_010), 42_000)
        @test current_context_tokens(cutter, fake_conv(20_000)) == 42_000 + round(Int, 0.5 * 14_990)
    end
end
