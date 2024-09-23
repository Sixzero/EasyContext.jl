
using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

Base.@kwdef struct CohereRerankerPro <: AbstractReranker
    model::String = "rerank-english-v2.0"
    top_n::Int = 10
end

function (reranker::CohereRerankerPro)(result::RAGContext, args...)
    reranked = rerank(reranker, result.chunk.sources, result.chunk.contexts, result.question)
    return RAGContext(SourceChunk(reranked.sources, reranked.contexts), result.question)
end

function rerank(
    reranker::CohereRerankerPro,
    sources::AbstractVector{<:AbstractString},
    chunks::AbstractVector{<:AbstractString},
    question::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = false
)
    reranked = RAG.rerank(RAG.CohereReranker(model=reranker.model), question, chunks; top_n=top_n)
    
    reranked_sources = sources[reranked]
    reranked_chunks = chunks[reranked]
    
    return (sources=reranked_sources, contexts=reranked_chunks)
end

# Maintain compatibility with the existing RAG.rerank method
function RAG.rerank(
    reranker::CohereRerankerPro,
    index::AbstractDocumentIndex,
    question::AbstractString,
    candidates::AbstractCandidateChunks;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = false,
    kwargs...
)
    documents = index[candidates, :chunks]
    sources = index[candidates, :sources]
    reranked = rerank(reranker, sources, documents, question; top_n, cost_tracker, verbose)
    
    reranked_positions = findall(s -> s in reranked.sources, sources)
    reranked_scores = [1.0 / i for i in 1:length(reranked_positions)]
    
    if candidates isa MultiCandidateChunks
        reranked_ids = [candidates.index_ids[i] for i in reranked_positions]
        return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
    else
        return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
    end
end


