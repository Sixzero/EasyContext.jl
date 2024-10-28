using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA

@kwdef mutable struct EmbeddingIndexBuilder <: AbstractIndexBuilder
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(;embedder=OpenAIBatchEmbedder(; model="text-embedding-3-small"))
    top_k::Int = 300
    force_rebuild::Bool = false
end

function get_index(builder::EmbeddingIndexBuilder, chunks::OrderedDict{String, String}; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    embeddings = RAG.get_embeddings(builder.embedder, collect(values(chunks),);
        verbose = verbose,
        cost_tracker)
    
    verbose && @info "Index built! (cost: $(round(cost_tracker[], digits=3)))"

    RAG.ChunkEmbeddingsIndex(;embeddings, chunks=collect(values(chunks)), sources=collect(keys(chunks)))
end

function (builder::EmbeddingIndexBuilder)(index, query::AbstractString)
    if isempty(index.chunks)
        @info "Empty index. Returning empty result."
        return OrderedDict{String, String}()
    end

    finder = RAG.CosineSimilarity()
    query_emb = RAG.get_embeddings(builder.embedder, [query], false, Threads.Atomic{Float64}(0.0), 80_000, 4)
    @assert query_emb isa AbstractMatrix
    @assert size(query_emb, 2) == 1
    query_emb = reshape(query_emb, :)
    
    positions, scores = RAG.find_closest(finder, RAG.chunkdata(index), query_emb; top_k=builder.top_k)
    
    sources = index.sources[positions]
    chunks = index.chunks[positions]
    
    OrderedDict(zip(sources, chunks))
end

get_embedder(builder::EmbeddingIndexBuilder) = builder.embedder

function get_finder(builder::EmbeddingIndexBuilder)
    RAG.CosineSimilarity()
end

function cache_key(builder::EmbeddingIndexBuilder, args...)
    embedder_type = typeof(get_embedder(builder)).name.name
    model_name = get_model_name(builder.embedder)
    hash_str = hash("$(args)_$(embedder_type)_$(model_name)")
    return bytes2hex(sha256("EmbeddingIndexBuilder_$hash_str"))
end

function cache_filename(builder::EmbeddingIndexBuilder, key::String)
    "embedding_index_$key.jld2"
end

# Export the constructor function if needed
export EmbeddingIndexBuilder

