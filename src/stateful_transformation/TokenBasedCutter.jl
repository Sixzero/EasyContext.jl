export TokenBasedCutter, estimate_conversation_tokens, token_usage_stats, cleanup_sources!

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
    target_ratio::Float64 = 0.3         # Target 30% after cutting

    # Safety
    min_keep_messages::Int = 4          # Always keep at least this many

    # Token estimation
    estimation_method::TokenEstimationMethod = CharCountDivTwo

    # Summarization
    summarizer_model::String = "claudeh"
    last_summary::String = ""

    # Track compaction to avoid double-summarization
    last_compaction_msg_count::Int = 0  # Message count after last compaction
end

"""
    get_effective_limit(cutter::TokenBasedCutter) -> Int

Get the effective context limit from explicit config or model lookup.
Returns 0 if not configured (disables token-based cutting).
"""
function get_effective_limit(cutter::TokenBasedCutter)
    cutter.context_limit > 0 && return cutter.context_limit
    isempty(cutter.model) && return 0
    return get_model_context_limit(cutter.model)
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
                startswith(v, "data:image") && continue
                total += estimate_tokens(v, method)
            end
        end
    end
    return total
end

estimate_conversation_tokens(cutter::TokenBasedCutter, conv) =
    estimate_conversation_tokens(conv, cutter.estimation_method)

"""
    estimate_message_tokens(msg, method::TokenEstimationMethod) -> Int

Estimate tokens for a single message.
"""
function estimate_message_tokens(msg, method::TokenEstimationMethod=CharCountDivTwo)
    total = estimate_tokens(msg.content, method)
    if hasproperty(msg, :context)
        for (_, v) in msg.context
            startswith(v, "data:image") && continue
            total += estimate_tokens(v, method)
        end
    end
    return total
end

function should_cut(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    limit = get_effective_limit(cutter)
    limit <= 0 && return false

    current_tokens = estimate_conversation_tokens(cutter, conv)
    threshold = limit * cutter.compact_threshold

    # Skip if we recently compacted and haven't added many messages
    # (prevents double-summarization in same turn)
    if cutter.last_compaction_msg_count > 0
        msgs_added = length(conv.messages) - cutter.last_compaction_msg_count
        if msgs_added <= 2  # Just AI response + tool results
            return false
        end
    end

    return current_tokens >= threshold
end

function calculate_keep(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    limit = get_effective_limit(cutter)
    target_tokens = limit > 0 ? round(Int, limit * cutter.target_ratio) : 60000

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

    # Summarize messages to be cut
    messages_to_cut = conv.messages[1:end-keep]
    cutter.last_summary = summarize_conversation(
        messages_to_cut;
        model=cutter.summarizer_model,
        previous_summary=cutter.last_summary
    )

    # Cut conversation
    cut_history!(conv; keep)

    # Prepend summary to first user message
    if !isempty(cutter.last_summary) && !isempty(conv.messages) && conv.messages[1].role == :user
        conv.messages[1].content = "<prior_context>\n$(cutter.last_summary)\n</prior_context>\n\n" * conv.messages[1].content
    end

    # Calculate tokens freed and clean up sources proportionally
    tokens_after = estimate_conversation_tokens(cutter, conv)
    tokens_freed = tokens_before - tokens_after

    # Ask SourceTracker which sources to remove to free up similar token budget
    # We free sources proportional to conversation tokens freed
    source_tokens_to_free = round(Int, tokens_freed * 0.5)  # Conservative: free half as much from sources
    sources_to_cut = get_sources_to_cut(source_tracker, source_tokens_to_free)
    remove_sources!(source_tracker, sources_to_cut, contexts...)

    # Track message count to prevent double-summarization
    cutter.last_compaction_msg_count = length(conv.messages)

    @info "TokenBasedCutter: cut conversation" kept=length(conv.messages) tokens_freed sources_removed=length(sources_to_cut)

    return cutter.last_summary
end

function get_cache_setting(cutter::TokenBasedCutter, conv, source_tracker::SourceTracker)
    limit = get_effective_limit(cutter)
    limit <= 0 && return :all

    current_tokens = estimate_conversation_tokens(cutter, conv)
    near_threshold = limit * (cutter.compact_threshold - 0.05)

    if current_tokens >= near_threshold
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
    current_tokens = estimate_conversation_tokens(cutter, conv)
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
        will_cut = context_limit > 0 && current_tokens >= threshold_tokens,
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
