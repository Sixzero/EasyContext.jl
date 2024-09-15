using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer
using Pkg
using AISH: get_project_files
using JLD2
using Snowball
import PromptingTools.Experimental.RAGTools as RAG
import Base: *

# Module-level constants
const CACHE_DIR = let
    dir = joinpath(dirname(dirname(@__DIR__)), "cache")
    isdir(dir) || mkpath(dir)
    dir
end


@kwdef mutable struct EmbeddingIndexBuilder <: AbstractIndexBuilder
    chunker::RAG.AbstractChunker = GolemSourceChunker()
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder()
    tagger::RAG.AbstractTagger = RAG.NoTagger()
    cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
end


@kwdef mutable struct BM25IndexBuilder <: AbstractIndexBuilder
    chunker::RAG.AbstractChunker = GolemSourceChunker()
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
    tagger::RAG.AbstractTagger = RAG.NoTagger()
    cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
end


@kwdef mutable struct JinaEmbeddingIndexBuilder <: AbstractIndexBuilder
    chunker::RAG.AbstractChunker = GolemSourceChunker()
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(
        embedder=JinaEmbedder(
            model="jina-embeddings-v2-base-code",
        ),
    )
    tagger::RAG.AbstractTagger = RAG.NoTagger()
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
    else isnothing(builder.cache)
        
        chunks, sources = result.chunk.contexts, result.chunk.sources
        processor=RAG.KeywordsProcessor()
        tagger=RAG.NoTagger()
        ## Tokenize and DTM
        dtm = RAG.get_keywords(processor, chunks;
            # verbose = verbose,
            cost_tracker)

        ## Extract tags
        tags_extracted = RAG.get_tags(tagger, chunks;
            verbose = verbose,
            cost_tracker)
        # Build the sparse matrix and the vocabulary
        tags, tags_vocab = RAG.build_tags(tagger, tags_extracted)

        verbose && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"
        
        index_id = gensym("ChunkKeywordsIndex")
        builder.cache = RAG.ChunkKeywordsIndex(; id = index_id, chunkdata = dtm, tags, tags_vocab, chunks, sources)
        JLD2.save(cache_file, "index", builder.cache)
    end
    return builder.cache
end

function get_index(builder::EmbeddingIndexBuilder, result::RAGContext; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    hash_str = hash("$(result.chunk.sources)")
    cache_file = joinpath(CACHE_DIR, "embedding_index_$(hash_str).jld2")

    if !isnothing(builder.cache)
        return builder.cache
    elseif isfile(cache_file)
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    else
        chunks, sources = result.chunk.contexts, result.chunk.sources
        embedder = builder.embedder
        tagger = builder.tagger

        embeddings = RAG.get_embeddings(embedder, chunks;
            verbose = verbose,
            cost_tracker)

        tags_extracted = RAG.get_tags(tagger, chunks;
            verbose = verbose,
            cost_tracker)
        tags, tags_vocab = RAG.build_tags(tagger, tags_extracted)

        verbose && @info "Index built! (cost: $(round(cost_tracker[], digits=3)))"

        index_id = gensym("ChunkEmbeddingsIndex")
        builder.cache = RAG.ChunkEmbeddingsIndex(; id = index_id, embeddings, tags, tags_vocab, chunks, sources)
        JLD2.save(cache_file, "index", builder.cache)
    end
    return builder.cache
end

function (builder::EmbeddingIndexBuilder)(result::RAGContext)
    index = get_index(builder, result)
    finder = RAG.CosineSimilarity()
    retriever = RAG.AdvancedRetriever(
        finder=finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )
    retrieved = RAG.retrieve(retriever, index, result.question; top_k=100, top_n=100, return_all=true)
    
    res = RAGContext(SourceChunk(retrieved.sources, retrieved.context), result.question)
    return res

end
function (builder::BM25IndexBuilder)(result::RAGContext)
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

function (builder::MultiIndexBuilder)(result::RAGContext)
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
get_embedder(builder::JinaEmbeddingIndexBuilder) = get_embedder(builder.embedder)
get_embedder(embedder::JinaEmbedder) = embedder
get_embedder(embedder::BatchEmbedder) = embedder
get_embedder(embedder::CachedBatchEmbedder) = get_embedder(embedder.embedder)

function *(a::AbstractIndexBuilder, b::Union{AbstractIndexBuilder, AbstractReranker})
    return x -> b(a(x))
end

# Index building functions
function build_index(builder::EmbeddingIndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
    hash_str = hash("$data")
    cache_file = joinpath(CACHE_DIR, "embedding_index_$(hash_str).jld2")

    if !force_rebuild && !isnothing(builder.cache)
        return builder.cache
    elseif !force_rebuild && isfile(cache_file)
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    end

    indexer = RAG.SimpleIndexer(;
        chunker = builder.chunker,
        embedder = builder.embedder,
        tagger = builder.tagger
    )

    index = RAG.build_index(indexer, data; verbose=verbose, embedder_kwargs=(model=get_model_name(indexer.embedder), verbose=verbose))

    JLD2.save(cache_file, "index", index)
    builder.cache = index

    return index
end

function build_index(builder::BM25IndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
    hash_str = hash("$data")
    cache_file = joinpath(CACHE_DIR, "bm25_index_$(hash_str).jld2")

    if !force_rebuild && !isnothing(builder.cache)
        return builder.cache
    elseif !force_rebuild && isfile(cache_file)
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    end

    indexer = RAG.KeywordsIndexer(
        chunker = builder.chunker,
        processor = builder.processor,
        tagger = builder.tagger
    )

    index = RAG.build_index(indexer, data; verbose=verbose)

    JLD2.save(cache_file, "index", index)
    builder.cache = index

    return index
end

function build_index(builder::JinaEmbeddingIndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
    hash_str = hash("$data")
    cache_file = joinpath(CACHE_DIR, "jina_embedding_index_$(hash_str).jld2")

    if !force_rebuild && !isnothing(builder.cache)
        return builder.cache
    elseif !force_rebuild && isfile(cache_file)
        builder.cache = JLD2.load(cache_file, "index")
        return builder.cache
    end

    indexer = RAG.SimpleIndexer(;
        chunker = builder.chunker,
        embedder = builder.embedder,
        tagger = builder.tagger
    )

    index = RAG.build_index(indexer, data; verbose=verbose, embedder_kwargs=(model=get_model_name(indexer.embedder), verbose=verbose))

    JLD2.save(cache_file, "index", index)
    builder.cache = index

    return index
end

function build_index(builder::MultiIndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
    if !force_rebuild && !isnothing(builder.cache)
        return builder.cache, map(b -> get_finder(b), builder.builders)
    end

    indices = map(b -> build_index(b, data; force_rebuild=force_rebuild, verbose=verbose), builder.builders)
    finders = map(b -> get_finder(b), builder.builders)

    multi_index = RAG.MultiIndex(indices)
    builder.cache = multi_index

    return multi_index, finders
end

function build_multi_index(; verbose::Bool=true, force_rebuild::Bool=false, use_async::Bool=true)
    builders = [
        EmbeddingIndexBuilder(force_rebuild=force_rebuild, verbose=verbose),
        BM25IndexBuilder(force_rebuild=force_rebuild, verbose=verbose),
        JinaEmbeddingIndexBuilder(force_rebuild=force_rebuild, verbose=verbose)
    ]

    indices = asyncmap(build_index, builders)

    multi_index = RAG.MultiIndex(indices)

    return multi_index
end

function get_finder(builder::EmbeddingIndexBuilder)
    RAG.CosineSimilarity()
end

function get_finder(builder::BM25IndexBuilder)
    RAG.BM25Similarity()
end

function get_finder(builder::JinaEmbeddingIndexBuilder)
    RAG.CosineSimilarity()
end


# Exports
export build_index, build_multi_index, get_context, get_answer
