export TokenBasedCutter, estimate_conversation_tokens, token_usage_stats, cleanup_sources!, record_real_usage!, current_context_tokens

"""
TokenBasedCutter triggers cutting based on token usage.
Triggers at `compact_threshold`% of the context limit, then keeps the most recent
`max_keep_ratio` of messages (min `min_keep_messages`) and summarizes the rest.
Keeping ~20% of recent messages lands post-cut context around ~25-30% of the limit,
since recent messages carry most of the tokens - no separate token target needed.

Always summarizes old messages before cutting.
Uses SourceTracker for token-aware source cleanup.
"""
@kwdef mutable struct TokenBasedCutter <: AbstractCutter
    # Context limit configuration
    context_limit::Int = 0          # 0 = auto from model, >0 = explicit limit
    model::String = ""              # Model name for auto context_limit lookup

    # Trigger threshold (ratio of context_limit)
    compact_threshold::Float64 = 0.8    # Start compacting at 80% of limit
    target_ratio::Float64 = 0.2         # Reporting only (token_usage_stats target)

    # How much to keep
    min_keep_messages::Int = 4          # Always keep at least this many
    max_keep_ratio::Float64 = 0.2       # Keep this fraction of recent messages

    # Token estimation
    estimation_method::TokenEstimationMethod = CharCountDivTwo

    # Summarization
    summarizer_model::String = "claudeh"
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

# Beyond 200K, extended context trades quality/cost for length — cap compaction limit
# TODO: Sync context limits from a single source of truth (e.g. model config shared between frontend & backend)
#       so we don't need hardcoded caps duplicated across ContextIndicator.tsx and here.
#       Ideally the backend returns the effective compaction limit per model and the frontend just displays it.
const STANDARD_CONTEXT_CAP = 200_000

"""
    get_effective_limit(cutter::TokenBasedCutter) -> Int

Get the effective context limit from explicit config or model lookup.
Caps at STANDARD_CONTEXT_CAP to match frontend behavior — extended context
beyond 200K degrades quality and increases cost, so we compact earlier.
Returns 0 if not configured (disables token-based cutting).
"""
function get_effective_limit(cutter::TokenBasedCutter)
    cutter.context_limit > 0 && return cutter.context_limit
    isempty(cutter.model) && return 0
    return min(get_model_context_limit(cutter.model), STANDARD_CONTEXT_CAP)
end

"""
    estimate_conversation_tokens(conv, method::TokenEstimationMethod) -> Int

Estimate total tokens in a conversation (messages + context).
"""
function estimate_conversation_tokens(conv, method::TokenEstimationMethod=CharCountDivTwo)
    total = 0
    for msg in conv.messages
        total += estimate_tokens(msg.content, method)
        if hasproperty(msg, :context)
            for (_, v) in msg.context
                startswith(v, "data:") && continue  # skip base64 media (images, PDFs)
                total += estimate_tokens(v, method)
            end
        end
    end
    return total
end

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
    # Shift the current anchor into prev, but only when the estimate actually moved:
    # two anchors at (near-)identical estimates give a meaningless slope. Keep the
    # last distinct pair so the affine fit stays well-conditioned.
    if cutter.last_real_estimate > 0 && abs(est - cutter.last_real_estimate) > 1
        cutter.prev_real_tokens = cutter.last_real_tokens
        cutter.prev_real_estimate = cutter.last_real_estimate
    end
    cutter.last_real_tokens = real_tokens
    cutter.last_real_estimate = est
    nothing
end

# CharCountDivTwo (chars/2) roughly tracks real tokens, but the ratio varies a lot
# by content (plain text vs tool JSON vs skipped media), so we never assume a fixed
# factor. Used only as the slope for a single-anchor (through-overhead) estimate.
const DEFAULT_EST_TO_REAL_RATIO = 0.5

"""
    context_model(cutter::TokenBasedCutter) -> (overhead::Float64, slope::Float64)

Affine map from conversation-estimate tokens to real context tokens:
`real ≈ overhead + slope·estimate`. `overhead` is the fixed non-conversation
context (system prompt, tools, skills — invisible to the char estimate); `slope`
is the content's real-per-estimate ratio.

With two distinct anchors we fit both from the line through them (clamping to keep
overhead ≥ 0 and slope > 0). With one anchor we can't separate the two, so we
attribute everything to the conversation (overhead 0, slope = real/estimate) —
still content-adaptive, unlike the old fixed 0.5. With none, slope defaults and
overhead is 0.
"""
function context_model(cutter::TokenBasedCutter)
    r1, e1 = cutter.last_real_tokens, cutter.last_real_estimate
    r0, e0 = cutter.prev_real_tokens, cutter.prev_real_estimate
    have1 = r1 > 0 && e1 > 0
    have0 = r0 > 0 && e0 > 0
    if have1 && have0 && abs(e1 - e0) > 1
        slope = (r1 - r0) / (e1 - e0)
        # Reject noisy/degenerate fits (e.g. real up while estimate down): fall back to
        # the single-anchor proportional slope. Real content runs ~0.25–8× the estimate.
        if 0.25 <= slope <= 8.0
            overhead = max(0.0, r1 - slope * e1)              # clamp: overhead can't be negative
            return (overhead, slope)
        end
    end
    have1 && return (0.0, r1 / e1)                            # single anchor → proportional
    return (0.0, DEFAULT_EST_TO_REAL_RATIO)
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

"""
    estimate_message_tokens(msg, method::TokenEstimationMethod) -> Int

Estimate tokens for a single message.
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

function should_cut(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    limit = get_effective_limit(cutter)
    limit <= 0 && return false

    current_tokens = current_context_tokens(cutter, conv)
    threshold = limit * cutter.compact_threshold
    current_tokens < threshold && return false

    # Only compact if a cut would actually drop a real message. Right after a
    # compaction the kept window (or a single oversized message) can still exceed
    # the threshold; re-cutting then frees nothing and just re-summarizes the same
    # prefix forever. would_free_messages is the principled stop for that churn.
    return would_free_messages(conv, calculate_keep(cutter, conv, source_tracker))
end

function calculate_keep(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    n = length(conv.messages)
    # Keep a fixed fraction of recent messages (default 20%), never fewer than the
    # minimum. Message-count is a robust proxy that avoids the token-budget trap
    # where oversized recent messages (tool dumps, file reads) each blow the budget
    # yet still get kept, so removing many tiny old ones frees almost nothing.
    # history_cut_start later aligns the boundary back to a :user turn, so the final
    # kept count can be slightly higher to keep a turn's tool_use/tool_result intact.
    keep_count = max(cutter.min_keep_messages, floor(Int, n * cutter.max_keep_ratio))
    return min(keep_count, n)
end

function do_cut!(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker, contexts...; keep::Union{Int,Nothing}=nothing)
    keep = something(keep, calculate_keep(cutter, conv, source_tracker))
    n = length(conv.messages)

    n <= keep && return cutter.last_summary

    # Calculate tokens being freed (for source cleanup)
    tokens_before = estimate_conversation_tokens(cutter, conv)

    summarize_and_cut!(cutter, conv; keep)

    # Calculate tokens freed and clean up sources proportionally
    tokens_after = estimate_conversation_tokens(cutter, conv)
    tokens_freed = tokens_before - tokens_after

    # Ask SourceTracker which sources to remove to free up similar token budget
    # We free sources proportional to conversation tokens freed
    source_tokens_to_free = round(Int, tokens_freed * 0.5)  # Conservative: free half as much from sources
    sources_to_cut = get_sources_to_cut(source_tracker, source_tokens_to_free)
    remove_sources!(source_tracker, sources_to_cut, contexts...)

    @info "TokenBasedCutter: cut conversation" kept=length(conv.messages) tokens_freed sources_removed=length(sources_to_cut)

    return cutter.last_summary
end

function get_cache_setting(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    limit = get_effective_limit(cutter)
    limit <= 0 && return :all

    current_tokens = current_context_tokens(cutter, conv)
    near_threshold = limit * (cutter.compact_threshold - 0.05)

    # Only skip caching the last block if a compaction is actually imminent — i.e. it
    # would free a real message. Otherwise we'd disable caching forever whenever the
    # kept window alone sits near the threshold (nothing left to compact).
    if current_tokens >= near_threshold &&
       would_free_messages(conv, calculate_keep(cutter, conv, source_tracker))
        @info "Not caching - near compacting threshold" current_tokens near_threshold
        return :all_but_last
    end
    return :all
end

"""
    token_usage_stats(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker) -> NamedTuple

Get current token usage statistics for debugging/monitoring.
"""
function token_usage_stats(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    context_limit = get_effective_limit(cutter)
    current_tokens = current_context_tokens(cutter, conv)
    source_tokens = get_total_tokens(source_tracker)
    threshold_tokens = context_limit > 0 ? context_limit * cutter.compact_threshold : 0
    target_tokens = context_limit > 0 ? context_limit * cutter.target_ratio : 0

    (
        current_tokens = current_tokens,
        source_tokens = source_tokens,
        total_tracked = current_tokens + source_tokens,
        context_limit = context_limit,
        threshold_tokens = round(Int, threshold_tokens),
        target_tokens = round(Int, target_tokens),
        percentage_used = context_limit > 0 ? round(100 * current_tokens / context_limit; digits=1) : 0.0,
        messages_count = length(conv.messages),
        sources_count = length(source_tracker.sources),
        will_cut = should_cut(cutter, conv, source_tracker),
        would_keep = calculate_keep(cutter, conv, source_tracker),
    )
end

"""
    cleanup_sources!(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker, contexts...)

Clean up old sources without conversation compaction.
Call this post-session to ensure source cleanup happens even if conversation compaction was skipped.
"""
function cleanup_sources!(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker, contexts...)
    isempty(contexts) && return String[]

    limit = get_effective_limit(cutter)
    limit <= 0 && return String[]

    # Calculate how many source tokens we should keep
    # Target: sources should be proportional to conversation tokens
    conv_tokens = estimate_conversation_tokens(cutter, conv)
    target_source_tokens = round(Int, conv_tokens * 0.5)  # Sources ~50% of conv tokens

    current_source_tokens = get_total_tokens(source_tracker)
    tokens_to_free = current_source_tokens - target_source_tokens

    tokens_to_free <= 0 && return String[]

    sources_to_cut = get_sources_to_cut(source_tracker, tokens_to_free)
    remove_sources!(source_tracker, sources_to_cut, contexts...)

    !isempty(sources_to_cut) && @info "Source cleanup" sources_removed=length(sources_to_cut) tokens_freed=tokens_to_free

    return sources_to_cut
end
