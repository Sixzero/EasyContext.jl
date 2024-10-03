using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA

@kwdef mutable struct MultiIndexBuilder <: AbstractIndexBuilder
    builders::Vector{<:AbstractIndexBuilder}=[
        with_cache(EmbeddingIndexBuilder()),
        with_cache(BM25IndexBuilder()),
    ]
    top_k::Int=200
end

function get_index(builder::MultiIndexBuilder, result::RAGContext; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    indices = [get_index(b, result; cost_tracker, verbose) for b in builder.builders]
    return RAG.MultiIndex(indices)
end

function cache_key(builder::MultiIndexBuilder, args...)
    builder_hashes = [cache_key(b, args...) for b in builder.builders]
    return bytes2hex(sha256("MultiIndexBuilder_$(join(builder_hashes, "_"))"))
end

function cache_filename(builder::MultiIndexBuilder, key::String)
    return "multi_index_$key.jld2"
end
