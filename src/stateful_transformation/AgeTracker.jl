export AgeTracker, cut_old_sources!, cut_old_conversation_history!, force_compact!

@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    max_history::Int = 14
    cut_to::Int = 6
    age::Int = 0
    last_message_count::Int = 0
    # Summarization
    summarizer_model::String = "claudeh"
    last_summary::String = ""
end

function register_changes!(ager::AgeTracker, tracker::ChangeTracker)
    for (source, state) in tracker.changes
        if state === :UPDATED || state === :NEW
            ager.tracker[source] = ager.age
        end
    end
end

function cut_old_sources!(sources_to_delete::Vector{String}, ctx::Context, ct::ChangeTracker) 
    cut_old_sources!(sources_to_delete, ctx.d, ct)
end

function cut_old_sources!(sources_to_delete::Vector{String}, ctx::OrderedDict, ct::ChangeTracker)
    for source in sources_to_delete
        delete!(ctx, source)
        delete!(ct.changes, source)
        delete!(ct.chunks_dict, source)
    end
    return sources_to_delete
end

"""
    do_compact!(age_tracker::AgeTracker, conv::Session, keep::Int) -> String

Core compaction logic: summarize messages being cut, then cut, then prepend summary.
Returns the generated summary.
"""
function do_compact!(age_tracker::AgeTracker, conv::Session, keep::Int)
    length(conv.messages) <= keep && return age_tracker.last_summary

    # Summarize messages to be cut
    messages_to_cut = conv.messages[1:end-keep]
    age_tracker.last_summary = summarize_conversation(
        messages_to_cut;
        model=age_tracker.summarizer_model,
        previous_summary=age_tracker.last_summary
    )

    # Cut
    conv.messages = conv.messages[end-keep+1:end]

    # Prepend summary to first kept user message
    if !isempty(age_tracker.last_summary) && !isempty(conv.messages) && conv.messages[1].role == :user
        conv.messages[1].content = "<prior_context>\n$(age_tracker.last_summary)\n</prior_context>\n\n" * conv.messages[1].content
    end

    age_tracker.last_message_count = length(conv.messages)
    return age_tracker.last_summary
end

function cut_old_conversation_history!(age_tracker::AgeTracker, conv::Session, contexts...)
    current_msg_count = length(conv.messages)
    age_tracker.age += current_msg_count - age_tracker.last_message_count

    if current_msg_count >= age_tracker.max_history
        keep = age_tracker.cut_to - (conv.messages[end - age_tracker.cut_to + 1].role === :assistant)

        do_compact!(age_tracker, conv, keep)

        # Clean up old source trackers
        min_age = age_tracker.age - age_tracker.cut_to
        sources_to_delete = String[]
        for (source, age) in age_tracker.tracker
            if age < min_age
                push!(sources_to_delete, source)
            end
        end
        for (; tracker_context, changes_tracker) in contexts
            cut_old_sources!(sources_to_delete, tracker_context, changes_tracker)
        end
        for source in sources_to_delete
            delete!(age_tracker.tracker, source)
        end
    end
    age_tracker.last_message_count = length(conv.messages)
    return false
end

function get_cache_setting(tracker::AgeTracker, conv::Session)
    messages_count = length(conv.messages)
    if messages_count >= tracker.max_history - 1
        @info "We do not cache, because next message will trigger a cut!"
        return :all_but_last
    end
    return :all
end

"""
    force_compact!(age_tracker::AgeTracker, conv::Session; keep=nothing) -> String

Explicitly trigger conversation compaction regardless of message count.
Useful for manual "/compact" command or when context feels bloated.
Returns the generated summary.
"""
function force_compact!(age_tracker::AgeTracker, conv::Session; keep=nothing)
    keep = something(keep, age_tracker.cut_to)
    summary = do_compact!(age_tracker, conv, keep)
    !isempty(summary) && @info "Conversation compacted" kept=length(conv.messages) summary_length=length(summary)
    return summary
end
