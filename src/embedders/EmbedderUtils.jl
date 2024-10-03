using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer, AbstractEmbedder
using JLD2, Snowball, Pkg
import PromptingTools.Experimental.RAGTools as RAG
import Base: *

abstract type AbstractIndexBuilder end
abstract type AbstractEasyEmbedder <: AbstractEmbedder end

include("OpenAIBatchEmbedder.jl")
include("JinaEmbedder.jl")
include("VoyageEmbedder.jl")
include("CacheBatchEmbedder.jl")
include("CombinedIndexBuilder.jl")
include("EmbeddingIndexBuilder.jl")
include("BM25IndexBuilder.jl")
include("MultiIndexBuilder.jl")

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

# Add this function after the cache functions
function with_cache(builder::AbstractIndexBuilder)
    return CachedLoader(loader=builder, cache_dir=CACHE_DIR)
end

function *(a::AbstractIndexBuilder, b::Union{AbstractIndexBuilder, RAG.AbstractReranker})
    return x -> b(a(x))
end

# Exports
export build_index, build_multi_index, get_context, get_answer


