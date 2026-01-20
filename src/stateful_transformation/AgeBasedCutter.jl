export AgeBasedCutter

"""
AgeBasedCutter triggers cutting based on message count.
Simple and predictable: cut at `max_messages`, keep `keep_messages`.

Uses SourceTracker's age-based cleanup: sources older than keep window are removed.
"""
@kwdef mutable struct AgeBasedCutter <: AbstractCutter
    max_messages::Int = 14      # Trigger cut when message count reaches this
    keep_messages::Int = 6      # Keep this many messages after cut
    summarize::Bool = false     # Whether to generate summary before cutting
    summarizer_model::String = "claudeh"
    last_summary::String = ""
end

function should_cut(cutter::AgeBasedCutter, conv, source_tracker::SourceTracker)
    return length(conv.messages) >= cutter.max_messages
end

function calculate_keep(cutter::AgeBasedCutter, conv, source_tracker::SourceTracker)
    n = length(conv.messages)
    keep = min(cutter.keep_messages, n)

    # Adjust to not start with assistant message
    if keep > 0 && keep <= n
        cut_start = n - keep + 1
        if conv.messages[cut_start].role === :assistant && keep > 1
            keep -= 1
        end
    end

    return keep
end

function do_cut!(cutter::AgeBasedCutter, conv, source_tracker::SourceTracker, contexts...; keep::Union{Int,Nothing}=nothing)
    keep = something(keep, calculate_keep(cutter, conv, source_tracker))
    n = length(conv.messages)

    n <= keep && return cutter.last_summary

    # Optional: summarize before cutting
    if cutter.summarize
        messages_to_cut = conv.messages[1:end-keep]
        cutter.last_summary = summarize_conversation(
            messages_to_cut;
            model=cutter.summarizer_model,
            previous_summary=cutter.last_summary
        )
    end

    # Cut conversation
    cut_history!(conv; keep)

    # Prepend summary to first message if we have one
    if cutter.summarize && !isempty(cutter.last_summary) && !isempty(conv.messages) && conv.messages[1].role == :user
        conv.messages[1].content = "<prior_context>\n$(cutter.last_summary)\n</prior_context>\n\n" * conv.messages[1].content
    end

    # Clean up old sources
    # Sources older than (current_age - keep) are removed
    min_age = source_tracker.current_age - keep
    sources_to_cut = get_sources_older_than(source_tracker, min_age)
    remove_sources!(source_tracker, sources_to_cut, contexts...)

    @info "AgeBasedCutter: cut conversation" kept=length(conv.messages) sources_removed=length(sources_to_cut)

    return cutter.last_summary
end

function get_cache_setting(cutter::AgeBasedCutter, conv, source_tracker::SourceTracker)
    messages_count = length(conv.messages)
    if messages_count >= cutter.max_messages - 1
        @info "Not caching - next message will trigger cut"
        return :all_but_last
    end
    return :all
end
