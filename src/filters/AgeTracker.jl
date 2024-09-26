const Age = Int
const AgeTracker = Dict{String, Age}

function (tracker::AgeTracker)(src_content::Context; max_history::Int)
    for source in keys(src_content); tracker[source] = get(tracker, source, 0) + 1; end

    for (source, age) in tracker
        age ≥ max_history && (delete!(tracker, source); delete!(src_content, source))
    end
    src_content
end