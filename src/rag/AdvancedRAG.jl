using Dates
using SHA
using EasyContext: create_openai_embedder, create_jina_embedder, create_voyage_embedder
using PromptingTools.Experimental.RAGTools: ChunkEmbeddingsIndex, AbstractChunkIndex


# Main search interface for EmbeddingSearch
@kwdef struct TwoLayerRAG <: AbstractRAGConfig
    topK::TopK
    reranker::AbstractReranker
end

# Convenience constructor for vector of embedders
function TwoLayerRAG(embedders::Vector{<:AbstractEmbedder}, reranker::AbstractReranker; k::Int=50, method::Symbol=:max)
    TwoLayerRAG(top_k=TopK(embedders, method; topK=k), reranker=reranker)
end

function search(method::TwoLayerRAG, chunks::Vector{T}, query::AbstractString; rerank_query::Union{AbstractString, Nothing}=nothing) where T
    rerank_query = rerank_query === nothing ? query : rerank_query
    results = search(method.topK, chunks, query)
    rerank(method.reranker, results, rerank_query)
end

humanize(m::AbstractRAGConfig) = 
    "$(humanize(m.topK))\n$(humanize(m.reranker))"
