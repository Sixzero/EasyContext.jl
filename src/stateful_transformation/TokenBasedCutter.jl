export TokenBasedCutter, estimate_conversation_tokens, token_usage_stats, cleanup_sources!, record_real_usage!, current_context_tokens

"""
TokenBasedCutter triggers cutting based on token usage.
Adaptive: triggers at `compact_threshold`% of context limit, targets `target_ratio`% after cut.

Always summarizes old messages before cutting.
Uses SourceTracker for token-aware source cleanup.
"""
@kwdef mutable struct TokenBasedCutter <: AbstractCutter
    # Context limit configuration
    context_limit::Int = 0          # 0 = auto from model, >0 = explicit limit
    model::String = ""              # Model name for auto context_limit lookup

    # Thresholds (as ratios of context_limit)
    compact_threshold::Float64 = 0.8    # Trigger at 80% of limit
    target_ratio::Float64 = 0.2         # Target 20% after cutting

    # Safety
    min_keep_messages::Int = 4          # Always keep at least this many
    max_keep_ratio::Float64 = 0.2       # Never keep more than this fraction of messages

    # Token estimation
    estimation_method::TokenEstimationMethod = CharCountDivTwo

    # Summarization
    summarizer_model::String = "claudeh"
    last_summary::String = ""

    # Real-usage anchor: the provider's exact context size from the last API call,
    # plus our char-estimate of the conversation at that same moment. Current size is
    # then `real + (estimate_now - estimate_then)` - only the DELTA since the last
    # real measurement is ever estimated, so the number stays accurate (including
    # system prompt/tools/skills, which the char estimate alone is blind to).
    last_real_tokens::Int = 0
    last_real_estimate::Int = 0
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
    cutter.last_real_tokens = real_tokens
    cutter.last_real_estimate = estimate_conversation_tokens(cutter, conv)
    nothing
end

# CharCountDivTwo (chars/2) roughly tracks real tokens, but the ratio varies a lot
# by content (plain text vs tool JSON vs skipped media). Rather than assume a fixed
# factor, we derive it empirically from the anchor: real/estimate at the last API call.
const DEFAULT_EST_TO_REAL_RATIO = 0.5

"""
    est_to_real_ratio(cutter::TokenBasedCutter) -> Float64

Real tokens per estimate-token, measured at the anchor (`real / estimate`). Falls
back to a default until a usable anchor exists. This adapts to the actual content
mix instead of assuming chars/2 ≈ 2× real, which can be off by several times.
"""
function est_to_real_ratio(cutter::TokenBasedCutter)
    (cutter.last_real_tokens > 0 && cutter.last_real_estimate > 0) || return DEFAULT_EST_TO_REAL_RATIO
    cutter.last_real_tokens / cutter.last_real_estimate
end

"""
    current_context_tokens(cutter::TokenBasedCutter, conv) -> Int

Current context size, scaled from the last real API measurement by how much the
conversation estimate has grown/shrunk since the anchor:
`real * (estimate_now / estimate_anchor)`. Proportional scaling keeps the system
prompt/tools/skills overhead baked into `real` and moving with conversation size,
without trying to separate a fixed overhead term (which is unidentifiable from a
single anchor and produced wildly wrong values when real/estimate diverged).
Exact at the anchor; re-anchored on every real API usage. Falls back to the raw
char estimate when no real usage has been recorded yet.
"""
function current_context_tokens(cutter::TokenBasedCutter, conv)
    est = estimate_conversation_tokens(cutter, conv)
    (cutter.last_real_tokens > 0 && cutter.last_real_estimate > 0) || return est
    round(Int, cutter.last_real_tokens * (est / cutter.last_real_estimate))
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
    limit = get_effective_limit(cutter)
    target_real = limit > 0 ? round(Int, limit * cutter.target_ratio) : 60000
    # Messages below are counted in conversation-estimate units; convert the target
    # from real tokens to estimate units using the anchor's measured ratio. The
    # overhead (system prompt/tools/skills) is already folded into the real anchor
    # and scales with the conversation, so we don't subtract a separate term (which
    # was unidentifiable and blew up when real/estimate diverged).
    ratio = est_to_real_ratio(cutter)
    target_tokens = round(Int, target_real / ratio)

    messages = conv.messages
    n = length(messages)
    n <= cutter.min_keep_messages && return n

    # Calculate from end: how many messages fit in target budget
    total_tokens = 0
    keep_count = 0

    for i in n:-1:1
        msg_tokens = estimate_message_tokens(messages[i], cutter.estimation_method)
        if total_tokens + msg_tokens <= target_tokens || keep_count < cutter.min_keep_messages
            total_tokens += msg_tokens
            keep_count += 1
        else
            break
        end
    end

    # Cap by message-count fraction: when recent messages are oversized, the
    # token budget alone keeps only a few messages that still carry most of the
    # context (e.g. long tool outputs). Forcing them into the summary instead
    # keeps the retained tail small (~max_keep_ratio of the chat) and actually
    # reaches the target token budget.
    keep_cap = max(cutter.min_keep_messages, floor(Int, n * cutter.max_keep_ratio))
    keep_count = min(keep_count, keep_cap)

    # Ensure minimum and adjust for assistant start
    keep_count = max(keep_count, cutter.min_keep_messages)

    if keep_count > 0 && keep_count < n
        cut_start = n - keep_count + 1
        if messages[cut_start].role !== :user
            # Expand keep to include the preceding :user message
            keep_count += 1
        end
    end

    return keep_count
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
