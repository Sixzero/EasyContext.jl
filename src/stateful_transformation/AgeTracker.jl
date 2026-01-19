export AgeTracker, cut_old_sources!, register_changes!

"""
AgeTracker tracks the "age" of context sources for cleanup during compacting.
When conversation is compacted, old sources that haven't been referenced recently are removed.

This is a simple struct focused only on source tracking.
For conversation compacting, use ContextCompactor.
"""
@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    age::Int = 0
    last_message_count::Int = 0
end

"""
    register_changes!(tracker::AgeTracker, changes::ChangeTracker)

Register source changes, updating their age to current.
"""
function register_changes!(tracker::AgeTracker, changes::ChangeTracker)
    for (source, state) in changes.changes
        if state === :UPDATED || state === :NEW
            tracker.tracker[source] = tracker.age
        end
    end
end

"""
    update_age!(tracker::AgeTracker, conv::Session)

Update the age counter based on message count changes.
"""
function update_age!(tracker::AgeTracker, conv::Session)
    current_msg_count = length(conv.messages)
    tracker.age += current_msg_count - tracker.last_message_count
    tracker.last_message_count = current_msg_count
end

"""
    cut_old_sources!(tracker::AgeTracker, keep_count::Int, contexts...)

Remove sources older than the kept message window.
Call this after compacting to clean up stale source references.
"""
function cut_old_sources!(tracker::AgeTracker, keep_count::Int, contexts...)
    min_age = tracker.age - keep_count
    sources_to_delete = String[]

    for (source, age) in tracker.tracker
        if age < min_age
            push!(sources_to_delete, source)
        end
    end

    for (; tracker_context, changes_tracker) in contexts
        cut_old_sources!(sources_to_delete, tracker_context, changes_tracker)
    end

    for source in sources_to_delete
        delete!(tracker.tracker, source)
    end

    return sources_to_delete
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
