
using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractReranker
const RAG = RAGTools


Base.@kwdef struct CohereRerankerPro <: AbstractReranker
    model::String = "rerank-english-v2.0"
    top_n::Int = 10
end

function (reranker::CohereRerankerPro)(chunks::OrderedDict{<:AbstractString, <:AbstractString}, query::AbstractString)
    reranked = rerank(reranker, chunks, query)
    return reranked
end

function rerank(
    reranker::CohereRerankerPro,
    chunks::OrderedDict{<:AbstractString, <:AbstractString},
    query::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = false
)
    sources = collect(keys(chunks))
    contents = collect(values(chunks))
    
    reranked_indices = RAG.rerank(RAG.CohereReranker(model=reranker.model), query, contents; top_n=top_n)
    
    reranked_sources = sources[reranked_indices]
    reranked_chunks = contents[reranked_indices]
    
    return OrderedDict(zip(reranked_sources, reranked_chunks))
end

# Maintain compatibility with the existing RAG.rerank method
function RAG.rerank(
    reranker::CohereRerankerPro,
    index::RAG.AbstractDocumentIndex,
    query::AbstractString,
    candidates::RAG.AbstractCandidateChunks;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = false,
    kwargs...
)
    documents = index[candidates, :chunks]
    sources = index[candidates, :sources]
    chunks = OrderedDict(zip(sources, documents))
    reranked = rerank(reranker, chunks, query; top_n, cost_tracker, verbose)
    
    reranked_positions = findall(s -> s in keys(reranked), sources)
    reranked_scores = [1.0 / i for i in 1:length(reranked_positions)]
    
    if candidates isa MultiCandidateChunks
        reranked_ids = [candidates.index_ids[i] for i in reranked_positions]
        return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
    else
        return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
    end
end


