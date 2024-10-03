using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA

@kwdef mutable struct EmbeddingIndexBuilder <: AbstractIndexBuilder
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(;embedder=OpenAIBatchEmbedder(; model="text-embedding-3-small"))
    top_k::Int = 300
    force_rebuild::Bool = false
end

function get_index(builder::EmbeddingIndexBuilder, chunks::OrderedDict{String, String}; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    embedder = builder.embedder

    embeddings = RAG.get_embeddings(embedder, collect(values(chunks));
        verbose = verbose,
        cost_tracker)
    
    verbose && @info "Index built! (cost: $(round(cost_tracker[], digits=3)))"

    index_id = gensym("ChunkEmbeddingsIndex")
    index = RAG.ChunkEmbeddingsIndex(; id = index_id, embeddings, chunks=collect(values(chunks)), sources=collect(keys(chunks)))
    @info "Successfully built embedding index! Size: $(size(embeddings))"
    return index
end

function (builder::EmbeddingIndexBuilder)(chunks::OrderedDict{String, String}, query::AbstractString)
    if isempty(chunks)
        return OrderedDict{String, String}()
    end
    index = get_index(builder, chunks)
    finder = RAG.CosineSimilarity()
    retriever = RAG.AdvancedRetriever(
        finder=finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )
    retrieved = RAG.retrieve(retriever, index, query; top_k=builder.top_k, top_n=builder.top_k, return_all=true)
    
    return OrderedDict(zip(retrieved.sources, retrieved.context))
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
    return "embedding_index_$key.jld2"
end
