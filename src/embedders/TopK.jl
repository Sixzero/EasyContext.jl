using LinearAlgebra

DEFAULT_TOP_K = 50
"""
    TopK{T<:AbstractEmbedder}

A struct for handling top-N selection with flexible embedder combinations.

# Fields
- `embedder::Union{AbstractEmbedder,MultiEmbedderCombiner}`: Single embedder or combiner
- `top_k::Int`: Number of top results to return
"""
@kwdef struct TopK{T<:Union{AbstractEmbedder,MultiEmbedderCombiner}} <: AbstractRAGConfig
    embedder::T
    top_k::Int = DEFAULT_TOP_K
end

# Default constructor for vector of embedders uses MaxScoreEmbedder
function TopK(embedders::Vector{<:AbstractEmbedder}; method::Symbol=:max, top_k::Int=DEFAULT_TOP_K)
    embedder = if method === :weighted && length(embedders) > 0
        weights = fill(1.0/length(embedders), length(embedders))
        WeighterEmbedder(weights, embedders)
    elseif method === :rrf
        RRFScoreEmbedder(embedders)
    elseif method === :mean
        MeanScoreEmbedder(embedders)
    elseif method === :max
        MaxScoreEmbedder(embedders)
    else
        throw(ArgumentError("Unknown method: $method. Use :max, :mean, :rrf, :weighted or provide weights directly."))
    end
    TopK(embedder=embedder, top_k=top_k)
end

# Single embedder constructor
TopK(embedder::AbstractEmbedder; top_k::Int=DEFAULT_TOP_K) = TopK(embedder=[embedder]; top_k)

# Main interface
function search(topn::TopK, chunks::AbstractVector{T}, query::AbstractString) where T
    scores = get_score(topn.embedder, chunks, query)
    topN(scores, chunks, topn.top_k)
end

# Add humanize method
humanize(t::TopK) = "Top$(t.top_k)($(humanize(t.embedder)))"

# Export humanize
export humanize
