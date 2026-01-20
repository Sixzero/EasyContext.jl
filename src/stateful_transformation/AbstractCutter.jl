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
