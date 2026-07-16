export AbstractCutter, should_cut, do_cut!, maybe_cut!, get_cache_setting, calculate_keep

"""
AbstractCutter defines the interface for conversation cutters.

Implementations:
- AgeBasedCutter: triggers at message count threshold
- TokenBasedCutter: triggers at token usage threshold

All cutters work with SourceTracker for source cleanup.
"""
abstract type AbstractCutter end

"""
    should_cut(cutter::AbstractCutter, conv, source_tracker::SourceTracker) -> Bool

Check if cutting should be triggered.
"""
function should_cut end

"""
    calculate_keep(cutter::AbstractCutter, conv, source_tracker::SourceTracker) -> Int

Calculate how many messages to keep after cutting.
"""
function calculate_keep end

"""
    do_cut!(cutter::AbstractCutter, conv, source_tracker::SourceTracker, contexts...; keep=nothing) -> String

Perform the cut. Returns summary (may be empty for non-summarizing cutters).
If `keep` is provided, overrides the auto-calculated keep count.
Handles:
1. Summarization (if supported)
2. Message cutting
3. Source cleanup via SourceTracker
"""
function do_cut! end

"""
    maybe_cut!(cutter::AbstractCutter, conv, source_tracker::SourceTracker, contexts...) -> Bool

Check if cutting is needed and do it if so. Returns true if cut was performed.
"""
function maybe_cut!(cutter::AbstractCutter, conv, source_tracker::SourceTracker, contexts...)
    if should_cut(cutter, conv, source_tracker)
        do_cut!(cutter, conv, source_tracker, contexts...)
        return true
    end
    return false
end

"""
    get_cache_setting(cutter::AbstractCutter, conv, source_tracker::SourceTracker) -> Symbol

Get cache setting based on proximity to cutting threshold.
Returns :all or :all_but_last.
"""
function get_cache_setting end

# ── Shared compaction primitives ──────────────────────────────────────────────
# The running summary is carried INSIDE the conversation as a single leading
# `<prior_context>` user message (the persistence layer reloads it from a message
# attachment, so it must live in `conv.messages`, not only in `cutter.last_summary`).
# These helpers keep that lifecycle in ONE place for every summarizing cutter.

"""
    would_free_messages(conv, keep::Int) -> Bool

True only if cutting to `keep` would remove a real conversation message. When the
prefix to drop is empty or contains only the leading `<prior_context>` message,
re-cutting frees nothing — so callers must not compact, otherwise they churn
(re-summarize + re-attach the same summary) without making progress. This is the
principled replacement for the old `last_compaction_msg_count` heuristic.
"""
function would_free_messages(conv, keep::Int)
    cut_start = history_cut_start(conv.messages, keep)
    cut_start <= 1 && return false
    any(!is_prior_context, @view conv.messages[1:cut_start-1])
end

"""
    summarize_and_cut!(cutter::AbstractCutter, conv; keep::Int) -> String

Summarize the prefix `cut_history!(; keep)` is about to remove, cut the history,
and re-attach the running summary as the single leading `<prior_context>` message.
Uses the SAME aligned boundary for summarizing and cutting, so the summarized set
and the removed set always agree. Returns the updated `cutter.last_summary`.
"""
function summarize_and_cut!(cutter::AbstractCutter, conv; keep::Int)
    # Nothing real to drop: don't re-summarize and don't re-attach a duplicate
    # <prior_context> message. Guards manual/age-based callers that skip should_cut.
    would_free_messages(conv, keep) || return cutter.last_summary
    cut_start = history_cut_start(conv.messages, keep)
    messages_to_cut = conv.messages[1:cut_start-1]
    cutter.last_summary = summarize_conversation(messages_to_cut;
        model=cutter.summarizer_model, previous_summary=cutter.last_summary)
    cut_history!(conv; keep)
    if !isempty(cutter.last_summary)
        # NOTE: the message MUST start with "<prior_context>" — is_prior_context keys on it.
        pushfirst!(conv.messages,
            create_user_message("<prior_context>\nThis session is continued from an earlier portion of the conversation that was compacted to save context. The summary below is the only record of it — treat it as what actually happened.\n\n$(cutter.last_summary)\n</prior_context>"))
    end
    return cutter.last_summary
end
