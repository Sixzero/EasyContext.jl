export TokenBasedCutter, estimate_conversation_tokens, token_usage_stats, record_real_usage!,
       current_context_tokens, get_effective_limit

"""
TokenBasedCutter triggers cutting based on token usage.
Triggers at `compact_threshold`% of the context limit, then keeps the most recent
messages worth ~`target_ratio` of the limit in tokens (min `min_keep_messages`) and
summarizes the rest. The kept window is chosen by walking back from the newest message
and accumulating estimated tokens — not by a fixed message-count fraction, which frees
far fewer tokens than expected when recent messages (tool dumps, file reads) are large.

Always summarizes old messages before cutting.
"""
@kwdef mutable struct TokenBasedCutter <: AbstractCutter
    # Context limit configuration
    context_limit::Int = 0          # 0 = auto from model, >0 = explicit limit
    model::String = ""              # Model name for auto context_limit lookup

    # A limit the provider actually ENFORCED (per-key/per-tier caps are invisible to
    # our model table, and only a rejected request reveals them). Kept apart from the
    # configured `context_limit` so it neither overwrites a deliberate override nor
    # survives a switch to a model it was never observed on.
    enforced_limit::Int = 0
    enforced_limit_model::String = ""

    # Trigger threshold (ratio of context_limit)
    compact_threshold::Float64 = 0.8    # Start compacting at 80% of limit
    target_ratio::Float64 = 0.2         # Post-cut token target: keep recent messages worth ~this fraction of limit

    # How much to keep
    min_keep_messages::Int = 4          # Always keep at least this many
    max_keep_ratio::Float64 = 0.2       # Fallback message-count fraction when no context limit is set

    # Token estimation
    estimation_method::TokenEstimationMethod = CharCountDivTwo

    # Summarization. `summarizer` is the callable so tests can stay offline without
    # redefining the global one (a redefinition would leak into every later test).
    summarizer_model::String = SUMMARIZER_MODEL
    summarizer::Function = summarize_conversation
    last_summary::String = ""

    # Real-usage anchors: the provider's exact context size from API calls, paired
    # with our char-estimate of the conversation at that same moment. Two anchors let
    # us fit an affine map `real ≈ overhead + slope·estimate`, where `overhead` is the
    # fixed non-conversation context (system prompt, tools, skills — which the char
    # estimate is blind to) and `slope` is the content's real-tokens-per-estimate ratio.
    # `prev_*` holds the older anchor; both default to 0 (no anchor yet).
    last_real_tokens::Int = 0
    last_real_estimate::Int = 0
    prev_real_tokens::Int = 0
    prev_real_estimate::Int = 0
end

# Quality/cost cap regardless of the model's advertised window (1M-context models
# degrade and get expensive well before their limit). Also keeps the compaction
# threshold (80% → 160K) aligned with the frontend indicator, which renders the
# ring against the same 200K standard cap.
const CONTEXT_CAP = 200_000

"""
    get_effective_limit(cutter::TokenBasedCutter) -> Int

Get the effective context limit: an explicit `context_limit` is respected as-is
(deliberate override); model lookup is capped at `CONTEXT_CAP`.
Returns 0 if not configured (disables token-based cutting).
"""
function get_effective_limit(cutter::TokenBasedCutter)
    configured = cutter.context_limit > 0 ? cutter.context_limit :
                 isempty(cutter.model) ? 0 : min(get_model_context_limit(cutter.model), CONTEXT_CAP)
    enforced = cutter.enforced_limit_model == cutter.model ? cutter.enforced_limit : 0
    enforced > 0 || return configured
    return configured > 0 ? min(configured, enforced) : enforced
end

"""
    estimate_message_tokens(msg, method) -> Int

Estimate tokens in a single message (content + context). The per-message building
block for `estimate_conversation_tokens`, so both stay in sync.
"""
function estimate_message_tokens(msg, method::TokenEstimationMethod=CharCountDivTwo)
    total = estimate_tokens(msg.content, method)
    if hasproperty(msg, :context)
        for (_, v) in msg.context
            startswith(v, "data:") && continue  # skip base64 media (images, PDFs)
            total += estimate_tokens(v, method)
        end
    end
    return total
end

estimate_conversation_tokens(conv, method::TokenEstimationMethod=CharCountDivTwo) =
    sum(msg -> estimate_message_tokens(msg, method), conv.messages; init=0)

estimate_conversation_tokens(cutter::TokenBasedCutter, conv) =
    estimate_conversation_tokens(conv, cutter.estimation_method)

"""
    record_real_usage!(cutter::TokenBasedCutter, conv, real_tokens::Int)

Anchor the cutter to an exact context size reported by the provider API
(prompt + cache read/write). Call it when `conv` reflects EXACTLY the messages
that were sent in that API call, so the paired estimate snapshot is aligned.
"""
function record_real_usage!(cutter::TokenBasedCutter, conv, real_tokens::Int)
    real_tokens <= 0 && return
    est = estimate_conversation_tokens(cutter, conv)
    # `last` must always be the NEWEST anchor (current_context_tokens estimates only the
    # delta since it). Promote the outgoing `last` into the `prev` baseline when either:
    # - there is no baseline yet (seed it; context_model won't fit until it's ≥200 away), or
    # - the new measurement is ≥MIN_ANCHOR_EST_DELTA from `last` (fresh well-separated pair).
    # Crucially, when growth is gradual (<200 per turn) the baseline is NOT overwritten, so
    # separation accumulates across turns and a two-anchor fit still becomes possible —
    # promoting on every turn would keep the pair forever too close to fit.
    if cutter.last_real_estimate > 0 &&
       (cutter.prev_real_estimate == 0 || abs(est - cutter.last_real_estimate) >= MIN_ANCHOR_EST_DELTA)
        cutter.prev_real_tokens = cutter.last_real_tokens
        cutter.prev_real_estimate = cutter.last_real_estimate
    end
    cutter.last_real_tokens = real_tokens
    cutter.last_real_estimate = est
    nothing
end

# CharCountDivTwo (chars/2) roughly tracks real tokens, but the ratio varies a lot
# by content (plain text vs tool JSON vs skipped media), so we never assume a fixed
# factor. Used as the slope whenever no trustworthy two-anchor fit is available.
const DEFAULT_EST_TO_REAL_RATIO = 0.5

# Minimum estimate-token separation between anchors for a slope fit. Below this the
# real-token delta is dominated by things the char estimate can't see (images, PDFs,
# system-message rebuilds), producing wild slopes.
const MIN_ANCHOR_EST_DELTA = 200

"""
    context_model(cutter::TokenBasedCutter) -> (overhead::Float64, slope::Float64)

Affine map from conversation-estimate tokens to real context tokens:
`real ≈ overhead + slope·estimate`. `overhead` is the fixed non-conversation
context (system prompt, tools, skills — invisible to the char estimate); `slope`
is the content's real-per-estimate ratio.

With two well-separated anchors we fit both from the line through them, accepting the
fit only when the slope is in a plausible content range AND the intercept is
non-negative (a negative intercept means the fixed-overhead assumption broke —
tools/system changed between anchors — so the line is not trustworthy). Otherwise we
fall back to the single latest anchor: default slope capped so overhead stays ≥ 0
(`slope = min(0.5, real/estimate)`, `overhead = real − slope·estimate`). The fallback
is exact at the anchor, so only the delta since the last LLM call is estimated.

The old single-anchor fallback did the opposite — proportional `slope = real/estimate`,
overhead 0 — which folded the large fixed system-prompt/tools/skills overhead (often
25K+ real tokens vs a ~2K conversation estimate) into the slope. Every conversation
token was then extrapolated 5–20×, firing auto-compaction when the REAL context was
only ~40–50K of a 200K limit.
"""
function context_model(cutter::TokenBasedCutter)
    r1, e1 = cutter.last_real_tokens, cutter.last_real_estimate
    r0, e0 = cutter.prev_real_tokens, cutter.prev_real_estimate
    have1 = r1 > 0 && e1 > 0
    have0 = r0 > 0 && e0 > 0
    have1 || return (0.0, DEFAULT_EST_TO_REAL_RATIO)
    if have0 && abs(e1 - e0) >= MIN_ANCHOR_EST_DELTA
        slope = (r1 - r0) / (e1 - e0)
        overhead = r1 - slope * e1
        # Accept only sane fits: plausible content slopes for chars/2 run ~0.25×
        # (ASCII prose/base64) to ~2.5× (CJK / dense unicode), and overhead must be
        # non-negative — a negative intercept means the fixed-overhead assumption
        # broke between the anchors, so the whole line is untrustworthy (clamping
        # just its intercept would keep a line through NEITHER anchor).
        if 0.25 <= slope <= 2.5 && overhead >= 0.0
            return (overhead, slope)
        end
    end
    # Single anchor / rejected fit → default slope through the anchor, capped so the
    # residual overhead stays ≥ 0. Exact at the anchor either way.
    slope = min(DEFAULT_EST_TO_REAL_RATIO, r1 / e1)
    return (r1 - slope * e1, slope)
end

"""
    current_context_tokens(cutter::TokenBasedCutter, conv) -> Int

Current context size from the affine model `overhead + slope·estimate_now`, so the
fixed system prompt/tools/skills overhead stays put while only the conversation part
scales with its estimate. Falls back to the raw char estimate before any anchor.
"""
function current_context_tokens(cutter::TokenBasedCutter, conv)
    est = estimate_conversation_tokens(cutter, conv)
    cutter.last_real_tokens > 0 && cutter.last_real_estimate > 0 || return est
    overhead, slope = context_model(cutter)
    round(Int, overhead + slope * est)
end

function should_cut(cutter::TokenBasedCutter, conv)
    limit = get_effective_limit(cutter)
    limit <= 0 && return false

    # No real-usage anchor yet (fresh flow, or one deserialized from a pre-anchor
    # blob): current_context_tokens falls back to the raw chars/2 estimate, which
    # overruns real tokens ~1.5-2x for ASCII and would fire compaction way too
    # early (e.g. at a real ~60K). The first LLM call always records an anchor
    # (record_real_usage!), so just wait for it.
    cutter.last_real_tokens > 0 || return false

    current_tokens = current_context_tokens(cutter, conv)
    threshold = limit * cutter.compact_threshold
    current_tokens < threshold && return false

    # Only compact if a cut would actually drop a real message. Right after a
    # compaction the kept window (or a single oversized message) can still exceed
    # the threshold; re-cutting then frees nothing and just re-summarizes the same
    # prefix forever. would_free_messages is the principled stop for that churn.
    return would_free_messages(conv, calculate_keep(cutter, conv))
end

function calculate_keep(cutter::TokenBasedCutter, conv)
    n = length(conv.messages)
    n <= cutter.min_keep_messages && return n

    limit = get_effective_limit(cutter)
    # No configured limit → token-based cutting is disabled; fall back to the old
    # message-count fraction for manual callers (should_cut already bails at limit<=0).
    limit <= 0 && return min(max(cutter.min_keep_messages, floor(Int, n * cutter.max_keep_ratio)), n)

    # Keep recent messages by TOKEN budget, not message count. Tokens are distributed
    # very unevenly (recent tool dumps / file reads dwarf old chat turns), so keeping a
    # fixed fraction of *messages* frees far fewer tokens than expected — 80% of messages
    # can be only ~40% of tokens, landing post-cut context near 50-60% of the limit.
    #
    # `target_ratio * limit` is the desired TOTAL post-cut context; the conversation's
    # share is that minus the fixed overhead (system prompt/tools/skills), converted from
    # real tokens into estimate space via the affine model's slope. Match should_cut's
    # units: before any real anchor it reads the raw estimate as-is (overhead 0, slope 1).
    anchored = cutter.last_real_tokens > 0 && cutter.last_real_estimate > 0
    overhead, slope = anchored ? context_model(cutter) : (0.0, 1.0)
    budget_est = max(0.0, (limit * cutter.target_ratio - overhead) / slope)

    # Always keep the newest min_keep_messages, then extend backward while the next
    # older message still fits the budget. history_cut_start later aligns the boundary
    # off :tool results, keeping a turn's tool_use/tool_result intact.
    first_kept = n - cutter.min_keep_messages + 1
    acc = sum(i -> estimate_message_tokens(conv.messages[i], cutter.estimation_method), first_kept:n; init=0)
    while first_kept > 1
        next = estimate_message_tokens(conv.messages[first_kept-1], cutter.estimation_method)
        acc + next > budget_est && break
        first_kept -= 1
        acc += next
    end
    return n - first_kept + 1
end

function do_cut!(cutter::TokenBasedCutter, conv; keep::Union{Int,Nothing}=nothing)
    keep = something(keep, calculate_keep(cutter, conv))
    n = length(conv.messages)

    n <= keep && return cutter.last_summary

    tokens_before = estimate_conversation_tokens(cutter, conv)
    summarize_and_cut!(cutter, conv; keep)
    tokens_freed = tokens_before - estimate_conversation_tokens(cutter, conv)

    @info "TokenBasedCutter: cut conversation" kept=length(conv.messages) tokens_freed

    return cutter.last_summary
end

function get_cache_setting(cutter::TokenBasedCutter, conv)
    limit = get_effective_limit(cutter)
    limit <= 0 && return :all

    current_tokens = current_context_tokens(cutter, conv)
    near_threshold = limit * (cutter.compact_threshold - 0.05)

    # Only skip caching the last block if a compaction is actually imminent — i.e. it
    # would free a real message. Otherwise we'd disable caching forever whenever the
    # kept window alone sits near the threshold (nothing left to compact).
    if current_tokens >= near_threshold &&
       would_free_messages(conv, calculate_keep(cutter, conv))
        @info "Not caching - near compacting threshold" current_tokens near_threshold
        return :all_but_last
    end
    return :all
end

"""
    force_shrink!(cutter::TokenBasedCutter, conv, real_tokens::Int, limit::Int) -> Bool

Emergency shrink after the provider rejected the request as too long (see the
AbstractCutter docstring). Deliberately NOT `maybe_cut!`: that path is gated on
`should_cut`, which stays false here forever, because it needs a real-usage anchor
and an anchor is only recorded from a SUCCESSFUL call. A conversation that is too
big on its first call therefore never self-corrects, and every retry resends the
same oversized payload. `real_tokens`/`limit` come from the error message — the one
place those exact numbers exist on a failed call.

Two stages, fixing two different failures:
 1. summarize + cut history — the ordinary "too much conversation";
 2. truncate a single oversized message — the case cutting CANNOT fix, since one
    message larger than the window survives every cut and would loop forever.
"""
# Smallest per-message cap worth producing. Below this, truncation keeps too little
# to be meaningful, so force_shrink! reports failure instead of mangling the message.
const MIN_FORCED_MSG_CHARS = 2_000

function force_shrink!(cutter::TokenBasedCutter, conv, real_tokens::Int, limit::Int)
    limit > 0 || return false
    tokens_before = estimate_conversation_tokens(cutter, conv)

    # The provider's exact count is an anchor the cutter could not obtain otherwise
    # (anchors normally come from successful calls), and it makes every later estimate
    # honest. Remember the enforced limit against the model it was observed on, so
    # later turns compact early enough — and a model switch drops it.
    real_tokens > 0 && record_real_usage!(cutter, conv, real_tokens)
    cutter.enforced_limit, cutter.enforced_limit_model = limit, cutter.model

    keep = calculate_keep(cutter, conv)
    would_free_messages(conv, keep) && summarize_and_cut!(cutter, conv; keep)

    # What survives cutting is a message so big it doesn't fit alone — a pasted
    # document, a huge tool result. Truncating in place is the only operation that
    # shrinks a conversation which cutting cannot. Cap it at half the post-cut token
    # target, converted to characters with the fitted slope (estimate = chars/2).
    _, slope = context_model(cutter)
    msg_cap_chars = round(Int, limit * cutter.target_ratio / max(slope, 0.05))
    if msg_cap_chars >= MIN_FORCED_MSG_CHARS
        for msg in conv.messages
            chars = length(msg.content)
            chars <= msg_cap_chars && continue
            # The result must fit the cap INCLUDING the marker, otherwise a truncated
            # message stays marginally over it and the next call shaves off a few more
            # characters — reporting "progress" forever instead of failing honestly.
            tail = msg_cap_chars ÷ 5
            marker(dropped) = "\n\n…[$dropped characters dropped — this message alone did not fit the model's context window]…\n\n"
            head = msg_cap_chars - tail - length(marker(chars))
            msg.content = string(first(msg.content, head), marker(chars - head - tail), last(msg.content, tail))
        end
    end

    tokens_after = estimate_conversation_tokens(cutter, conv)
    @warn "force_shrink!: context overflow recovery" real_tokens limit tokens=tokens_before=>tokens_after
    tokens_after < tokens_before
end

"""
    token_usage_stats(cutter::TokenBasedCutter, conv) -> NamedTuple

Get current token usage statistics for debugging/monitoring.
"""
function token_usage_stats(cutter::TokenBasedCutter, conv)
    context_limit = get_effective_limit(cutter)
    current_tokens = current_context_tokens(cutter, conv)
    threshold_tokens = context_limit > 0 ? context_limit * cutter.compact_threshold : 0
    target_tokens = context_limit > 0 ? context_limit * cutter.target_ratio : 0

    (
        current_tokens = current_tokens,
        context_limit = context_limit,
        threshold_tokens = round(Int, threshold_tokens),
        target_tokens = round(Int, target_tokens),
        percentage_used = context_limit > 0 ? round(100 * current_tokens / context_limit; digits=1) : 0.0,
        messages_count = length(conv.messages),
        will_cut = should_cut(cutter, conv),
        would_keep = calculate_keep(cutter, conv),
    )
end
