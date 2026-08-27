using Test
using EasyContext
using PromptingTools
using HTTP
using EasyContext: TokenBasedCutter, force_shrink!, should_cut, create_user_message,
                   create_AI_message, create_tool_message, Session, estimate_conversation_tokens,
                   get_effective_limit, recover_from_overflow!,
                   _is_context_overflow_error, parse_context_overflow

# Keep the emergency path offline: force_shrink! summarizes before cutting. Injected
# per cutter — redefining EasyContext.summarize_conversation would silently replace
# the real summarizer for every test file included after this one.
_fake_summary(msgs; kwargs...) = "SUMMARY of $(length(msgs)) messages"
_cutter(; kwargs...) = TokenBasedCutter(; model="claude-sonnet-4", summarizer=_fake_summary, kwargs...)

_chars(conv) = sum(m -> length(m.content), conv.messages; init=0)

@testset "context overflow detection" begin
    @testset "parses the counts the cutter cannot otherwise learn" begin
        # The exact error that motivated this path. On a FAILED call these numbers are
        # the only observation of the real context size — successes never happen here.
        real = "API Error (400): prompt is too long: 4210492 tokens > 1000000 maximum"
        @test _is_context_overflow_error(real)
        @test parse_context_overflow(real) == (used=4_210_492, limit=1_000_000)

        openai = "This model's maximum context length is 128000 tokens. However, your messages resulted in 189234 tokens. Please reduce the length of the messages."
        @test _is_context_overflow_error(openai)
        @test parse_context_overflow(openai) == (used=189_234, limit=128_000)

        @test parse_context_overflow("prompt is too long: 1,210,492 tokens > 200,000 maximum") ==
              (used=1_210_492, limit=200_000)
    end

    @testset "does not claim unrelated errors" begin
        # A false positive would summarize and truncate history to "fix" something
        # shrinking cannot fix — including byte/media size limits.
        for msg in ("API Error (429): rate_limit exceeded", "API Error (503): service unavailable",
                    "stream stalled", "econnreset", "invalid api key",
                    "API Error (413): request too large: image exceeds 5MB")
            @test !_is_context_overflow_error(msg)
        end
    end

    @testset "overflow without parsable numbers" begin
        @test _is_context_overflow_error("context_length_exceeded")
        @test parse_context_overflow("context_length_exceeded") === nothing
    end
end

@testset "recover_from_overflow!" begin
    # Guards the decision the retry hangs on: recover (true) vs. rethrow (false).
    OVERFLOW = ErrorException("API Error (400): prompt is too long: 4210492 tokens > 1000000 maximum")
    _cb(chunks...) = (c = PromptingTools.StreamCallback();
                      for t in chunks; push!(c.chunks, PromptingTools.StreamChunk(nothing, t, nothing)) end; c)
    _big() = Session(messages=[create_user_message(repeat("x", 5_400_000))])

    @testset "shrinks and asks for the resend" begin
        conv, cutter, retries, statuses = _big(), _cutter(), String[], String[]
        before = _chars(conv)
        @test recover_from_overflow!(OVERFLOW, cutter, conv, _cb();
            on_status=s -> push!(statuses, s),
            on_retry=(a, m, s, msg) -> push!(retries, msg))
        @test _chars(conv) < before                       # the resend carries less
        @test length(retries) == 1                        # the user is told why
        @test statuses == ["COMPACTING", "WORKING"]
    end

    @testset "never resends after content already streamed" begin
        # The user saw output from this attempt; a resend would duplicate it and mix
        # two attempts in the extractor.
        conv = _big()
        before = _chars(conv)
        @test !recover_from_overflow!(OVERFLOW, _cutter(), conv, _cb("partial answer"))
        @test _chars(conv) == before                      # and the session is untouched
    end

    @testset "declines what shrinking cannot fix" begin
        @test !recover_from_overflow!(OVERFLOW, nothing, _big(), _cb())                # no cutter
        # A user stop wins even when it arrives wrapped in something that reads like an
        # overflow — compacting on the way out would mutate the session as it shuts down.
        @test !recover_from_overflow!(InterruptException(), _cutter(), _big(), _cb())
        wrapped_stop = HTTP.RequestError("prompt is too long: 4210492 tokens > 1000000 maximum", InterruptException())
        @test EasyContext._is_context_overflow_error(wrapped_stop)   # it DOES read as overflow
        @test !recover_from_overflow!(wrapped_stop, _cutter(), _big(), _cb())
        @test !recover_from_overflow!(ErrorException("API Error (429): rate limit"), _cutter(), _big(), _cb())
        # Nothing left to free: returning true here would resend the same payload forever.
        tiny = Session(messages=[create_user_message("hi")])
        @test !recover_from_overflow!(OVERFLOW, _cutter(), tiny, _cb())
    end

    @testset "a failing on_retry callback does not sink the recovery" begin
        @test recover_from_overflow!(OVERFLOW, _cutter(), _big(), _cb();
            on_retry=(a, m, s, msg) -> error("UI gone"))
    end
end

@testset "force_shrink!" begin
    LIMIT = 1_000_000

    @testset "recovers a first-call overflow the normal path cannot" begin
        conv = Session(messages=[create_user_message("hi"), create_AI_message("hello"),
                                 create_user_message(repeat("x", 5_400_000))])  # a pasted paper
        cutter = _cutter()
        # Precondition: should_cut needs a real-usage anchor, and anchors only come
        # from SUCCESSFUL calls — so auto-compaction can never fire here.
        @test !should_cut(cutter, conv)

        @test force_shrink!(cutter, conv, 4_210_492, LIMIT)
        @test estimate_conversation_tokens(cutter, conv) < LIMIT
    end

    @testset "reports no progress instead of looping" begin
        # The retry is driven by this Bool: returning true when nothing shrank would
        # resend the same oversized payload forever.
        conv = Session(messages=[create_user_message(repeat("x", 5_400_000))])
        cutter = _cutter()
        @test force_shrink!(cutter, conv, 4_210_492, LIMIT)
        @test !force_shrink!(cutter, conv, 0, LIMIT)          # already at the cap
        @test !force_shrink!(_cutter(), Session(messages=[create_user_message("tiny")]), 0, LIMIT)
    end

    @testset "the enforced limit belongs to the model that hit it" begin
        # A per-key/per-tier cap is invisible to our model table, so remember it —
        # but pinning it permanently would keep compacting a 200K model at 50K after
        # the user switches away from the model that was actually capped.
        cutter = _cutter()
        force_shrink!(cutter, Session(messages=[create_user_message(repeat("z", 400_000))]), 0, 50_000)
        @test get_effective_limit(cutter) == 50_000
        cutter.model = "claude-opus-4"
        @test get_effective_limit(cutter) > 50_000
    end

    @testset "cuts history when no single message is oversized" begin
        conv = Session(messages=[create_user_message(repeat("a", 40_000)) for _ in 1:60])
        before = _chars(conv)
        @test force_shrink!(_cutter(), conv, 1_400_000, LIMIT)
        @test _chars(conv) < before
        @test length(conv.messages) < 60
    end

    @testset "tool pairing and roles survive truncation" begin
        # Truncation edits content in place; losing a tool_call_id or reordering roles
        # would turn the overflow 400 into a permanent malformed-request 400.
        conv = Session(messages=[create_user_message("go"),
                                 create_AI_message("calling"; tool_calls=[Dict{String,Any}("id" => "call_1")]),
                                 create_tool_message(repeat("R", 3_000_000), "call_1")])
        before = length(conv.messages[3].content)
        @test force_shrink!(_cutter(), conv, 4_000_000, LIMIT)
        @test length(conv.messages[3].content) < before     # the truncation did happen
        @test occursin("characters dropped", conv.messages[3].content)
        @test [m.role for m in conv.messages] == [:user, :assistant, :tool]
        @test conv.messages[3].tool_call_id == "call_1"
        @test conv.messages[2].tool_calls[1]["id"] == "call_1"
    end

    @testset "degenerate limits fail cleanly rather than throw" begin
        # An error-handling path must not raise a second error.
        for limit in (0, 1, 100, 4_000)
            conv = Session(messages=[create_user_message(repeat("q", 100_000))])
            @test force_shrink!(_cutter(), conv, 0, limit) isa Bool
        end
    end
end
