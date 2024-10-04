
@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    max_history::Int = 14
    cut_to::Int = 6
    age::Int=0
end

(tracker::AgeTracker)(src_content::Context) = tracker(src_content.d)
(tracker::AgeTracker)(src_content::OrderedDict) = begin
    tracker.age += 1
    for source in keys(src_content)
        source in keys(tracker.tracker) && continue 
        tracker.tracker[source] = tracker.age
    end
    src_content
end

function ageing!(tracker::AgeTracker, ctx::Context, ct::ChangeTracker)
    tracker.age += 1
    for (source, age) in tracker.tracker
        if tracker.age - tracker.max_history ≥ age 
            delete!(ctx.d, source)
            delete!(ct.changes, source)
            delete!(ct.content, source)
            delete!(tracker.tracker, source)
        end
    end
end

function get_cache_setting(tracker::AgeTracker, conv::Conversation) ## TODO recheck!!
    messages_count = length(conv.messages)
    if messages_count > tracker.max_history - 1
        @info "We do not cache, because next message will trigger a cut!"
        return nothing
    end
    return :last
end
