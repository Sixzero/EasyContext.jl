export AgeTracker, cut_old_sources!, cut_old_conversation_history!

@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    max_history::Int = 14
    cut_to::Int = 6
    age::Int = 0
    last_message_count::Int = 0
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

function cut_old_conversation_history!(age_tracker::AgeTracker, conv::Session, contexts...)
    current_msg_count = length(conv.messages)
    age_tracker.age += current_msg_count - age_tracker.last_message_count
    
    if current_msg_count >= age_tracker.max_history
        keep = age_tracker.cut_to - (conv.messages[end - age_tracker.cut_to + 1].role === :assistant)
        kept = cut_history!(conv; keep)
        min_age = age_tracker.age - age_tracker.cut_to
        sources_to_delete = String[]
        for (source, age) in age_tracker.tracker
            if age < min_age  # Changed < to <= to properly include threshold
                push!(sources_to_delete, source)
            end
        end
        for (; tracker_context, changes_tracker) in contexts
            cut_old_sources!(sources_to_delete, tracker_context, changes_tracker)
        end
        # Only delete from age_tracker after all contexts are processed
        for source in sources_to_delete
            delete!(age_tracker.tracker, source)
        end
    end
    age_tracker.last_message_count = length(conv.messages)
    return false
end

function get_cache_setting(tracker::AgeTracker, conv::Session) ## TODO recheck!!
    messages_count = length(conv.messages)
    if messages_count >= tracker.max_history - 1
        @info "We do not cache, because next message will trigger a cut!"
        return :all_but_last
    end
    return :all
end
