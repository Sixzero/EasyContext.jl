export AgeTracker, cut_old_history!

@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    max_history::Int = 14
    cut_to::Int = 6
    age::Int=0
end

function (ager::AgeTracker)(tracker::ChangeTracker)
    for (source, state) in tracker.changes
        if state === :UPDATED || state === :NEW
            ager.tracker[source] = ager.age
        end
    end
end

function cut_old_history!(age_tracker::AgeTracker, ctx::Context, ct::ChangeTracker)
    cut_old_history!(age_tracker, ctx.d, ct)
end
function cut_old_history!(age_tracker::AgeTracker, ctx::OrderedDict, ct::ChangeTracker)
    min_age = age_tracker.age - age_tracker.cut_to
    for (source, cont) in ctx
        if age_tracker.tracker[source] < min_age 
            delete!(ctx, source)
            delete!(ct.changes, source)
            delete!(ct.content, source)
            delete!(age_tracker.tracker, source)
        end
    end
end
function cut_old_history!(age_tracker::AgeTracker, conv::ConversationX, contexts...)
    age_tracker.age += 1    
    if length(conv.messages) > age_tracker.max_history
        keep = conv.messages[end-age_tracker.cut_to+1].role === :user ? age_tracker.cut_to : age_tracker.cut_to - 1
		keep = cut_history!(conv, keep=keep) 
        for (;tracker_context, changes_tracker) in contexts
            cut_old_history!(age_tracker, tracker_context, changes_tracker)
        end
	end
	return false
end

function get_cache_setting(tracker::AgeTracker, conv::ConversationX) ## TODO recheck!!
    messages_count = length(conv.messages)
    if messages_count >= tracker.max_history - 1
        @info "We do not cache, because next message will trigger a cut!"
        return nothing
    end
    return :last
end
