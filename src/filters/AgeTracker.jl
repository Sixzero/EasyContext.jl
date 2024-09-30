
const Age = Int

@kwdef mutable struct AgeTracker
    tracker::Dict{String, Age} = Dict{String, Age}()
end

function (tracker::AgeTracker)(src_content::Context; max_history::Int)
    for source in keys(src_content)
        tracker.tracker[source] = get(tracker.tracker, source, 0) + 1
    end

    for (source, age) in tracker.tracker
        if age ≥ max_history
            delete!(tracker.tracker, source)
            delete!(src_content, source)
        end
    end
    src_content
end

