using Dates
using SHA
using EasyContext: create_openai_embedder, create_jina_embedder, create_voyage_embedder
using PromptingTools.Experimental.RAGTools: ChunkEmbeddingsIndex, AbstractChunkIndex


abstract type AbstractRAGConfig end

# Main search interface for EmbeddingSearch
@kwdef struct TwoLayerRAG <: AbstractRAGConfig
    embedder::AbstractEmbedder
    reranker::AbstractReranker
    top_k::Int
end

function search(method::AbstractRAGConfig, chunks::Vector{T}, query::AbstractString; rerank_query::Union{AbstractString, Nothing}=nothing) where T
    rerank_query = rerank_query === nothing ? query : rerank_query
    score = get_score(method.embedder, chunks, query)
    results = topN(score, chunks, method.top_k)
    rerank(method.reranker, results, rerank_query)
end

humanize_config(m::AbstractRAGConfig) = 
    "$(humanize_config(m.embedder)), top_k=$(m.top_k)\n$(humanize_config(m.reranker))"
