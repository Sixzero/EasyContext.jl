using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra
using PromptingTools.Experimental.RAGTools: SimpleIndexer, AbstractEmbedder
using JLD2, Snowball, Pkg
import PromptingTools.Experimental.RAGTools as RAG
import Base: *


abstract type AbstractEasyEmbedder <: AbstractEmbedder end
abstract type AbstractRAGConfig end

include("SimilarityAlgos.jl")

include("api/BM25Embedder.jl")
include("api/OpenAIBatchEmbedder.jl")
include("api/JinaEmbedder.jl")
include("api/VoyageEmbedder.jl")

include("CachedBatchEmbedder.jl")
include("WeightingMethods.jl")
include("TopK.jl")

get_model_name(embedder::AbstractEasyEmbedder) = embedder.model
get_embedder(embedder::AbstractEasyEmbedder) = embedder
get_embedder_uniq_id(embedder::AbstractEasyEmbedder) = "$(typeof(get_embedder(embedder)).name.name)_$(get_model_name(embedder))"

# Module-level constants
const CACHE_DIR = let
    dir = joinpath(dirname(dirname(@__DIR__)), "cache")
    isdir(dir) || mkpath(dir)
    dir
end

# Exports
export build_index, build_multi_index, get_context, get_answer
export TopN
