using EasyRAGBench: RAGStore, append!
using OrderedCollections: OrderedDict
using Dates

"""
    IndexLogger(store_path::String)

Create an IndexLogger instance with a specified store path.

# Arguments
- `store_path::String`: The path where the RAGStore will be saved.

# Returns
- `IndexLogger`: An instance of IndexLogger.
"""
struct IndexLogger
    store::RAGStore
end

function IndexLogger(store_path::String)
    return IndexLogger(RAGStore(store_path))
end

"""
    log_index(logger::IndexLogger, index::AbstractChunkIndex, question::String)

Log an index and its associated question to the IndexLogger's RAGStore.

# Arguments
- `logger::IndexLogger`: The IndexLogger instance.
- `index::AbstractChunkIndex`: The index to log.
- `question::String`: The question associated with this index.

# Returns
- `String`: The ID of the newly added index.
"""
function log_index(logger::IndexLogger, index::Vector{<:AbstractChunkIndex}, question::String)
    log_index(logger, first(index), question)
end
function log_index(logger::IndexLogger, index::AbstractChunkIndex, question::String)
    index_dict = OrderedDict(zip(index.sources, index.chunks))
    question_tuple = (question=question, timestamp=Dates.now())
    index_id = append!(logger.store, index_dict, question_tuple)
    return index_id
end

"""
    get_logged_indices(logger::IndexLogger; start_date::DateTime=DateTime(0), end_date::DateTime=Dates.now(), 
                       question_filter::Union{String, Function}=x->true)

Retrieve logged indices from the IndexLogger's RAGStore, optionally filtered by date range and question content.

# Arguments
- `logger::IndexLogger`: The IndexLogger instance to query.
- `start_date::DateTime`: The start date for filtering (inclusive). Default is the beginning of time.
- `end_date::DateTime`: The end date for filtering (inclusive). Default is the current date and time.
- `question_filter::Union{String, Function}`: A string to search for in questions or a function that takes a question string and returns a boolean. Default is to include all questions.

# Returns
- `Vector{NamedTuple}`: A vector of NamedTuples containing index_id, question, and timestamp for each logged index.
"""
function get_logged_indices(logger::IndexLogger; start_date::DateTime=DateTime(0), end_date::DateTime=Dates.now(), 
                            question_filter::Union{String, Function}=x->true)
    log = get_index_log(logger.store)
    
    filtered_log = filter(log) do entry
        date_match = start_date <= entry.timestamp <= end_date
        question_match = if question_filter isa String
            occursin(question_filter, entry.question)
        else
            question_filter(entry.question)
        end
        date_match && question_match
    end
    
    return filtered_log
end
