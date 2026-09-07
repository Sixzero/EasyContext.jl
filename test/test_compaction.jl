using Test
using Dates: now, UTC
using EasyContext: Session, Message, cut_history!, history_cut_start,
    TokenBasedCutter, should_cut, record_real_usage!, would_free_messages,
    calculate_keep, create_user_message, create_AI_message

@testset "cut_history! tool boundary" begin
    mkmsgs() = begin
        c = Session()
        add!(role, content) = push!(c.messages, Message(timestamp=now(UTC), role=role, content=content))
        add!(:user, "u1"); add!(:assistant, "a1"); add!(:tool, "t1"); add!(:assistant, "a2")
        add!(:user, "u2"); add!(:assistant, "a3"); add!(:tool, "t2"); add!(:assistant, "a4")
        c.messages
    end
    msgs = mkmsgs()
    for k in 2:8
        cut_start = history_cut_start(msgs, k)
        # Window must never start on a :tool result (its paired tool_use would be
        # cut); :user and :assistant are both valid boundaries.
        @test msgs[cut_start].role != :tool
        # The removed prefix and the kept window partition the messages exactly —
        # no overlap (duplicate summary) and no gap (silent loss).
        @test cut_start >= 1 && cut_start <= length(msgs)
        kept_n = length(msgs) - cut_start + 1
        @test kept_n >= k
        # cut_history! mutates to the same boundary history_cut_start reports.
        c = Session(); append!(c.messages, deepcopy(msgs))
        cut_history!(c; keep=k)
        @test length(c.messages) == kept_n
        @test c.messages[1].role != :tool
    end

    # Long autonomous run: ONE user message then assistant/tool turns only.
    # The old :user-only alignment walked every boundary back to index 1,
    # deadlocking auto-compaction (nothing to free) until the next user message.
    autonomous = begin
        c = Session()
        push!(c.messages, Message(timestamp=now(UTC), role=:user, content="u1"))
        for i in 1:20
            push!(c.messages, Message(timestamp=now(UTC), role=:assistant, content="a$i"))
            push!(c.messages, Message(timestamp=now(UTC), role=:tool, content="t$i"))
        end
        c.messages
    end
    cut_start = history_cut_start(autonomous, 4)
    @test cut_start > 1                       # a cut is actually possible
    @test autonomous[cut_start].role != :tool
end

@testset "should_cut anchor gating" begin
    cutter = TokenBasedCutter(; context_limit=200_000)
    conv = Session()
    for i in 1:10
        push!(conv.messages, create_user_message("x"^100_000))
        push!(conv.messages, create_AI_message("y"^100_000))
    end

    # Raw chars/2 estimate is way above threshold, but with no real-usage anchor
    # the estimate overruns real tokens ~1.5-2x — must NOT fire yet.
    @test !should_cut(cutter, conv)

    # Anchored above the 160K threshold → fires.
    record_real_usage!(cutter, conv, 190_000)
    @test should_cut(cutter, conv)

    # Anchored below threshold → does not fire.
    cutter2 = TokenBasedCutter(; context_limit=200_000)
    record_real_usage!(cutter2, conv, 100_000)
    @test !should_cut(cutter2, conv)

    # Churn guard: when a cut would free nothing real, should_cut stays false even
    # above threshold (e.g. the kept window alone exceeds it).
    small = Session()
    push!(small.messages, create_user_message("u"^1_000_000))
    push!(small.messages, create_AI_message("a"))
    cutter3 = TokenBasedCutter(; context_limit=200_000)
    record_real_usage!(cutter3, small, 190_000)
    @test !would_free_messages(small, calculate_keep(cutter3, small))
    @test !should_cut(cutter3, small)
end

# A model-specific dispatch keeps these tests offline without replacing production methods.
struct CompactionTestModel end
const compaction_test_result = Ref{Any}("summary")
function EasyContext.aigenerate_with_config(::CompactionTestModel, prompt; kwargs...)
    result = compaction_test_result[]
    result isa Exception && throw(result)
    (; content=result)
end
Base.@kwdef mutable struct CompactionTestCutter <: EasyContext.AbstractCutter
    summarizer_model::CompactionTestModel = CompactionTestModel()
    last_summary::String = ""
    compacted_message_ids::Vector{String} = String[]
end
EasyContext.record_compacted_messages!(c::CompactionTestCutter, msgs) =
    append!(c.compacted_message_ids, (m.id for m in msgs if !EasyContext.is_prior_context(m)))

@testset "Compaction preserves history on summary failure" begin
    for old in ("", "previous summary"), result in (ErrorException("provider failed"), InterruptException(), " \n ")
        conv = Session(messages=[create_user_message("fact $i") for i in 1:6])
        before = copy(conv.messages)
        cutter = CompactionTestCutter(last_summary=old)
        compaction_test_result[] = result
        failure = try
            EasyContext.summarize_and_cut!(cutter, conv; keep=2)
            nothing
        catch e
            e
        end
        @test failure isa (result isa InterruptException ? InterruptException : ErrorException)
        @test conv.messages == before
        @test cutter.last_summary == old
        @test isempty(cutter.compacted_message_ids)
    end
end

@testset "Successful cuts track new messages and omit synthetic summaries" begin
    compaction_test_result[] = "first summary"
    conv = Session(messages=[create_user_message("fact $i") for i in 1:6])
    expected = [m.id for m in conv.messages[1:4]]
    cutter = CompactionTestCutter()
    EasyContext.summarize_and_cut!(cutter, conv; keep=2)
    @test length(conv.messages) == 3
    @test EasyContext.is_prior_context(first(conv.messages))
    @test cutter.compacted_message_ids == expected
    for i in 7:10
        push!(conv.messages, create_user_message("new fact $i"))
    end
    append!(expected, [m.id for m in conv.messages[2:end-2]])
    compaction_test_result[] = "merged summary"
    EasyContext.summarize_and_cut!(cutter, conv; keep=2)
    @test cutter.compacted_message_ids == expected
    @test first(conv.messages).content |> s -> occursin("merged summary", s)
    @test count(EasyContext.is_prior_context, conv.messages) == 1
    before = copy(conv.messages)
    EasyContext.summarize_and_cut!(cutter, conv; keep=2)
    @test conv.messages == before
    @test cutter.compacted_message_ids == expected

    real_cutter = TokenBasedCutter()
    EasyContext.record_compacted_messages!(real_cutter, conv.messages)
    @test real_cutter.compacted_message_ids == [m.id for m in conv.messages[2:end]]
end

@testset "keep validation" begin
    for conv in (Session(), Session(messages=[create_user_message("fact")]))
        for keep in (0, -1)
            @test_throws ArgumentError history_cut_start(conv.messages, keep)
            @test_throws ArgumentError cut_history!(conv; keep)
            @test_throws ArgumentError EasyContext.do_cut!(TokenBasedCutter(), conv; keep)
        end
        @test history_cut_start(conv.messages, 1) == 1
        @test EasyContext.do_cut!(TokenBasedCutter(), conv) == ""
    end
end

@testset "Empty anchored context does not auto-compact" begin
    cutter = TokenBasedCutter(context_limit=1000, last_real_tokens=2000, last_real_estimate=10)
    conv = Session()
    @test !should_cut(cutter, conv)
    @test EasyContext.get_cache_setting(cutter, conv) == :all
    @test !EasyContext.token_usage_stats(cutter, conv).will_cut
end
