using Dates
using SHA
using EasyContext: create_openai_embedder, create_jina_embedder, create_voyage_embedder
using RAGTools
using RAGTools: ChunkEmbeddingsIndex, AbstractChunkIndex

# Main search interface for EmbeddingSearch
@kwdef struct TwoLayerRAG <: AbstractRAGPipeline
    topK::AbstractRAGPipeline
    reranker::AbstractReranker
end

# Convenience constructor for vector of embedders
function TwoLayerRAG(embedders::Vector{<:RAGTools.AbstractEmbedder}, reranker::AbstractReranker; k::Int=50, method::Symbol=:max, verbose::Bool=false)
    TwoLayerRAG(topK=TopK(embedders, method; topK=k), reranker=reranker)
end


function search(method::TwoLayerRAG, chunks::Vector{T}, query::AbstractString; 
    rerank_query::Union{AbstractString, Nothing}=nothing,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    query_images::Union{AbstractVector{<:AbstractString}, Nothing}=nothing,
    request_id=nothing,
    ) where T
    
    rerank_query = rerank_query === nothing ? query : rerank_query
    results = search(method.topK, chunks, query; query_images, cost_tracker, request_id)
    return rerank(method.reranker, results, rerank_query; cost_tracker, query_images, request_id)
end

@kwdef mutable struct TwoLayerRAGWithTimings <: AbstractRAGPipeline
    topK::TopK
    reranker::AbstractReranker
    search_times::Vector{Float64} = Float64[]
    rerank_times::Vector{Float64} = Float64[]
end

function search(method::TwoLayerRAGWithTimings, chunks::Vector{T}, query::AbstractString; 
    rerank_query::Union{AbstractString, Nothing}=nothing,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    query_images::Union{AbstractVector{<:AbstractString}, Nothing}=nothing,
    request_id=nothing,
    ) where T
    
    rerank_query = rerank_query === nothing ? query : rerank_query

    start_search = time()
    results = search(method.topK, chunks, query; query_images, cost_tracker, request_id)
    push!(method.search_times, time() - start_search)

    start_rerank = time()
    final_results = rerank(method.reranker, results, rerank_query; cost_tracker, query_images, request_id)
    push!(method.rerank_times, time() - start_rerank)

    return final_results
end

humanize(m::AbstractRAGPipeline) = 
    "$(humanize(m.topK))\n$(humanize(m.reranker))"

# Predefined RAG pipeline configurations
"""
    EFFICIENT_PIPELINE(; top_n=10, rerank_prompt=create_rankgpt_prompt_v2, cache_prefix="workspace", verbose=0)

Creates an efficient RAG pipeline with a good balance between performance and accuracy.
Uses Cohere embedder and BM25 for retrieval with top_k=50, and ReduceGPTReranker with gem20f/gem15f models.

# Arguments
- `top_n::Int=10`: Number of documents to return after reranking
- `top_k::Int=50`: Number of documents retrieved by the initial search phase
- `rerank_prompt::Function=create_rankgpt_prompt_v2`: Function to create the reranking prompt
- `cache_prefix::String="workspace"`: Prefix for the embedder cache
- `verbose::Int=0`: Verbosity level (0=quiet, 1=normal, 2=detailed). If >1, returns timing-enabled pipeline.
"""
function EFFICIENT_PIPELINE(; top_n=10, top_k=50, rerank_prompt=create_rankgpt_prompt_v2, model::Union{AbstractString,Vector{String},ModelConfig}=["gemf", "grokfast"], cache_prefix="prefix", verbose=1)
    # embedder = create_openai_embedder(cache_prefix=cache_prefix)
    embedder_verbose = verbose > 0
    timing_enabled = verbose > 1
    embedder = EasyContext.create_cohere_embedder(model="embed-v4.0", cache_prefix=cache_prefix, verbose=embedder_verbose)
    bm25 = BM25Embedder()
    topK = TopK([embedder, bm25]; top_k)
    reranker = ReduceGPTReranker(batch_size=30; top_n, model, rerank_prompt, verbose)
    
    return timing_enabled ? TwoLayerRAGWithTimings(; topK, reranker) : TwoLayerRAG(; topK, reranker)
end

"""
    HIGH_ACCURACY_PIPELINE(; top_n=12, rerank_prompt=create_rankgpt_prompt_v2, cache_prefix="workspace", verbose=0)

Creates a high accuracy RAG pipeline optimized for precision over speed.
Uses Cohere embedder and BM25 for retrieval with top_k=120, and ReduceGPTReranker with gpt4om model.

# Arguments
- `top_n::Int=12`: Number of documents to return after reranking
- `top_k::Int=120`: Number of documents retrieved by the initial search phase
- `rerank_prompt::Function=create_rankgpt_prompt_v2`: Function to create the reranking prompt
- `cache_prefix::String="workspace"`: Prefix for the embedder cache
- `verbose::Int=0`: Verbosity level (0=quiet, 1=normal, 2=detailed). If >1, returns timing-enabled pipeline.
"""
function HIGH_ACCURACY_PIPELINE(; top_n=12, top_k=120, rerank_prompt=create_rankgpt_prompt_v2, model=["gem20f", "gem15f", "orqwenplus"], cache_prefix="prefix", verbose=0)
    # embedder = create_openai_embedder(cache_prefix=cache_prefix)
    embedder_verbose = verbose > 0
    timing_enabled = verbose > 1
    embedder = EasyContext.create_cohere_embedder(model="embed-v4.0", cache_prefix=cache_prefix, verbose=embedder_verbose)
    bm25 = BM25Embedder()
    topK = TopK([embedder, bm25]; top_k)
    reranker = ReduceGPTReranker(batch_size=40; top_n, model, rerank_prompt, verbose)
    
    return timing_enabled ? TwoLayerRAGWithTimings(; topK, reranker) : TwoLayerRAG(; topK, reranker)
end

"""
    EMPTY_PIPELINE(; verbose=0)

A no-op RAG pipeline that returns no results. Keeps the TwoLayerRAG interface but
uses null retrieval and reranker to avoid any work.
"""
function EMPTY_PIPELINE(; verbose=0)
    TwoLayerRAG(; topK=NullTopK(), reranker=NullReranker())
end

export EFFICIENT_PIPELINE, HIGH_ACCURACY_PIPELINE, EMPTY_PIPELINE
