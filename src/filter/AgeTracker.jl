
@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
end

(tracker::AgeTracker)(src_content::Context; max_history::Int, refresh_these::OrderedDict=OrderedDict()) = tracker(src_content.d; max_history=max_history, refresh_these=refresh_these)

function (tracker::AgeTracker)(src_content::OrderedDict; max_history::Int, refresh_these::OrderedDict=OrderedDict())
    foreach(source -> tracker.tracker[source] = get(tracker.tracker, source, 0) + 1, keys(src_content))
    foreach(source -> tracker.tracker[source] = 1, keys(refresh_these))

    for (source, age) in tracker.tracker
        if age ≥ max_history
            delete!(tracker.tracker, source)
            delete!(src_content, source)
        end
    end
    src_content
end

