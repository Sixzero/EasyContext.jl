using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer, AbstractEmbedder
using AISH: get_project_files
using JLD2, Snowball, Pkg
import PromptingTools.Experimental.RAGTools as RAG
import Base: *

abstract type AbstractIndexBuilder end
abstract type AbstractEasyEmbedder <: AbstractEmbedder end

include("OpenAIBatchEmbedder.jl")
include("JinaEmbedder.jl")
include("VoyageEmbedder.jl")
include("CacheBatchEmbedder.jl")

get_model_name(embedder::AbstractEasyEmbedder) = embedder.model
get_embedder(embedder::AbstractEasyEmbedder) = embedder
get_embedder_uniq_id(embedder::AbstractEasyEmbedder) = begin
  embedder_type = typeof(get_embedder(embedder)).name.name
  model_name = get_model_name(embedder)
  return "$(embedder_type)_$(model_name)"
end

# Module-level constants
const CACHE_DIR = let
    dir = joinpath(dirname(dirname(@__DIR__)), "cache")
    isdir(dir) || mkpath(dir)
    dir
end

@kwdef mutable struct EmbeddingIndexBuilder <: AbstractIndexBuilder
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(;embedder=OpenAIBatchEmbedder(; model="text-embedding-3-small"))
    cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
    top_k::Int = 300
    force_rebuild::Bool = false
end

@kwdef mutable struct BM25IndexBuilder <: AbstractIndexBuilder
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
    cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
end

@kwdef mutable struct MultiIndexBuilder <: AbstractIndexBuilder
    builders::Vector{<:AbstractIndexBuilder}=[
        EmbeddingIndexBuilder(),
        BM25IndexBuilder(),
        # JinaEmbeddingIndexBuilder()
    ]
    cache::Union{Nothing, RAG.MultiIndex} = nothing
    top_k::Int=200
end

function get_index(builder::BM25IndexBuilder, result::RAGContext; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)    
    hash_str = hash("$(result.chunk.sources)")
    cache_file = joinpath(CACHE_DIR, "bm25_index_$(hash_str).jld2")

    if !isnothing(builder.cache)
        return builder.cache
    elseif isfile(cache_file)
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    else
        chunks, sources = result.chunk.contexts, result.chunk.sources
        processor = builder.processor
        
        dtm = RAG.get_keywords(processor, chunks;
            verbose = verbose,
            cost_tracker)

        verbose && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"
        
        index_id = gensym("ChunkKeywordsIndex")
        builder.cache = RAG.ChunkKeywordsIndex(; id = index_id, chunkdata = dtm, chunks, sources)
        JLD2.save(cache_file, "index", builder.cache)
    end
    return builder.cache
end

function get_index(builder::EmbeddingIndexBuilder, result::RAGContext; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    hash_str = hash("$(result.chunk.sources)_$(get_model_name(builder.embedder))")
    cache_file = joinpath(CACHE_DIR, "embedding_index_$(hash_str).jld2")

    if !isnothing(builder.cache)
        return builder.cache
    elseif isfile(cache_file) && !builder.force_rebuild
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    else
        chunks, sources = result.chunk.contexts, result.chunk.sources
        embedder = builder.embedder

        embeddings = RAG.get_embeddings(embedder, chunks;
        verbose = verbose,
        cost_tracker)
        
        verbose && @info "Index built! (cost: $(round(cost_tracker[], digits=3)))"

        index_id = gensym("ChunkEmbeddingsIndex")
        builder.cache = RAG.ChunkEmbeddingsIndex(; id = index_id, embeddings, chunks, sources)
        @info "Successfully built embedding index! Size: $(size(embeddings))"
        JLD2.save(cache_file, "index", builder.cache)
    end
    return builder.cache
end

function (builder::EmbeddingIndexBuilder)(result::RAGContext, args...)
    index = get_index(builder, result)
    finder = RAG.CosineSimilarity()
    retriever = RAG.AdvancedRetriever(
        finder=finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )
    retrieved = RAG.retrieve(retriever, index, result.question; top_k=builder.top_k, return_all=true)
    
    res = RAGContext(SourceChunk(retrieved.sources, retrieved.context), result.question)
    return res
end

function (builder::BM25IndexBuilder)(result::RAGContext, args...)
    index = get_index(builder, result)
    finder = RAG.BM25Similarity()
    retriever = RAG.AdvancedRetriever(
        finder=finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )
    retrieved = RAG.retrieve(retriever, index, result.question; top_k=100, return_all=true)
    
    res = RAGContext(SourceChunk(retrieved.sources, retrieved.context), result.question)
    return res
end

function get_index(builder::MultiIndexBuilder, result::RAGContext; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    if !isnothing(builder.cache)
        return builder.cache
    else
        indices = [get_index(b, result; cost_tracker, verbose) for b in builder.builders]
        builder.cache = RAG.MultiIndex(indices)
    end
    return builder.cache
end

function (builder::MultiIndexBuilder)(result::RAGContext, args...)
    if isnothing(builder.cache) || length(result.chunk.contexts) != length(builder.cache.indices)
        builder.cache = RAG.MultiIndex([get_index(b, result) for b in builder.builders])
    end

    finders = [get_finder(b) for b in builder.builders]
    multi_finder = RAG.MultiFinder(finders)

    retriever = RAG.AdvancedRetriever(
        processor=RAG.KeywordsProcessor(),
        finder=multi_finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )

    retrieved = RAG.retrieve(retriever, builder.cache, result.question; top_k=builder.top_k, return_all=true)

    new_chunk = SourceChunk(retrieved.sources, retrieved.context)
    return RAGContext(new_chunk, result.question)
end

get_embedder(builder::EmbeddingIndexBuilder) = builder.embedder
get_embedder(embedder::RAG.BatchEmbedder) = embedder

function *(a::AbstractIndexBuilder, b::Union{AbstractIndexBuilder, RAG.AbstractReranker})
    return x -> b(a(x))
end

function get_finder(builder::EmbeddingIndexBuilder)
    RAG.CosineSimilarity()
end

function get_finder(builder::BM25IndexBuilder)
    RAG.BM25Similarity()
end

# Exports
export build_index, build_multi_index, get_context, get_answer


