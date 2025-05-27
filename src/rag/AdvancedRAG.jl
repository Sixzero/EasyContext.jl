using Dates
using SHA
using EasyContext: create_openai_embedder, create_jina_embedder, create_voyage_embedder
using RAGTools
using RAGTools: ChunkEmbeddingsIndex, AbstractChunkIndex



# Main search interface for EmbeddingSearch
@kwdef struct TwoLayerRAG <: AbstractRAGPipeline
    topK::TopK
    reranker::AbstractReranker
end

# Convenience constructor for vector of embedders
function TwoLayerRAG(embedders::Vector{<:RAGTools.AbstractEmbedder}, reranker::AbstractReranker; k::Int=50, method::Symbol=:max)
    TwoLayerRAG(top_k=TopK(embedders, method; topK=k), reranker=reranker)
end


function search(method::TwoLayerRAG, chunks::Vector{T}, query::AbstractString; 
    rerank_query::Union{AbstractString, Nothing}=nothing,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    query_images::Union{AbstractString, Nothing}=nothing,
    ) where T
    
    rerank_query = rerank_query === nothing ? query : rerank_query
    results = search(method.topK, chunks, query; query_images, cost_tracker)
    rerank(method.reranker, results, rerank_query; cost_tracker)
end

humanize(m::AbstractRAGPipeline) = 
    "$(humanize(m.topK))\n$(humanize(m.reranker))"

# Predefined RAG pipeline configurations
"""
    EFFICIENT_PIPELINE(; top_n=10, rerank_prompt=create_rankgpt_prompt_v2, cache_prefix="workspace")

Creates an efficient RAG pipeline with a good balance between performance and accuracy.
Uses Cohere embedder and BM25 for retrieval with top_k=50, and ReduceGPTReranker with gem20f/gem15f models.

# Arguments
- `top_n::Int=10`: Number of documents to return after reranking
- `rerank_prompt::Function=create_rankgpt_prompt_v2`: Function to create the reranking prompt
- `cache_prefix::String="workspace"`: Prefix for the embedder cache
"""
function EFFICIENT_PIPELINE(; top_n=10, rerank_prompt=create_rankgpt_prompt_v2, model=["gem20f", "gem15f", "orqwenplus"], cache_prefix="prefix")
    # embedder = create_openai_embedder(cache_prefix=cache_prefix)
    embedder = EasyContext.create_cohere_embedder(model="embed-v4.0", cache_prefix=cache_prefix)
    bm25 = BM25Embedder()
    topK = TopK([embedder, bm25]; top_k=50)
    reranker = ReduceGPTReranker(batch_size=30; top_n, model, rerank_prompt)
    
    TwoLayerRAG(; topK, reranker)
end

"""
    HIGH_ACCURACY_PIPELINE(; top_n=12, rerank_prompt=create_rankgpt_prompt_v2, cache_prefix="workspace")

Creates a high accuracy RAG pipeline optimized for precision over speed.
Uses Cohere embedder and BM25 for retrieval with top_k=120, and ReduceGPTReranker with gpt4om model.

# Arguments
- `top_n::Int=12`: Number of documents to return after reranking
- `rerank_prompt::Function=create_rankgpt_prompt_v2`: Function to create the reranking prompt
- `cache_prefix::String="workspace"`: Prefix for the embedder cache
"""
function HIGH_ACCURACY_PIPELINE(; top_n=12, rerank_prompt=create_rankgpt_prompt_v2, model=["gem20f", "gem15f", "orqwenplus"], cache_prefix="prefix")
    # embedder = create_openai_embedder(cache_prefix=cache_prefix)
    embedder = EasyContext.create_cohere_embedder(model="embed-v4.0", cache_prefix=cache_prefix)
    bm25 = BM25Embedder()
    topK = TopK([embedder, bm25]; top_k=120)
    reranker = ReduceGPTReranker(batch_size=40; top_n, model, rerank_prompt)
    
    TwoLayerRAG(; topK, reranker)
end

export EFFICIENT_PIPELINE, HIGH_ACCURACY_PIPELINE
