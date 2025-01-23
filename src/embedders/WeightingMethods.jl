abstract type MultiEmbedderCombiner <: AbstractEmbedder end

struct MaxScoreCombiner <: CombinationMethod end
struct WeightedCombiner <: CombinationMethod 
    weights::Vector{Float64}
end
struct RRFCombiner <: CombinationMethod end

function combine_scores(::MaxScoreCombiner, scores::AbstractVector{<:AbstractVector})
    n = length(first(scores))
    [maximum(s[i] for s in scores) for i in 1:n]
end

function combine_scores(::WeightedCombiner, scores::AbstractVector{<:AbstractVector})
    n = length(first(scores))
    [sum(w * s[i] for (w, s) in zip(c.weights, scores)) for i in 1:n]
end

function combine_scores(::RRFCombiner, scores::AbstractVector{<:AbstractVector})
    k = 60
    n = length(first(scores))
    [sum(1 / (k + s[i]) for s in scores) for i in 1:n]
end

function topN(score::AbstractVector{<:Real}, chunks::AbstractVector{T}, n::Int) where T
    sorted_indices = partialsortperm(score, 1:min(n, length(score)), rev=true)
    return chunks[sorted_indices]
end

struct WeighterEmbedder <: MultiEmbedderCombiner
    weights::Vector{Float64}
    embedders::Vector{AbstractEmbedder}
end

function get_score(c::WeighterEmbedder, chunks, query)
    scores = [get_score(embedder, chunks, query) for embedder in c.embedders]
    combine_scores(WeightedCombiner(c.combiner), scores)
end

struct MaxScoreEmbedder <: MultiEmbedderCombiner
    embedders::AbstractVector{AbstractEmbedder}
end

function get_score(c::MaxScoreEmbedder, chunks, query)
    scores = [get_score(embedder, chunks, query) for embedder in c.embedders]
    combine_scores(MaxScoreCombiner(), scores)
end

struct RRFScoreEmbedder <: MultiEmbedderCombiner
    embedders::AbstractVector{AbstractEmbedder}
end

function get_score(c::RRFScoreEmbedder, chunks, query)
    scores = [get_score(embedder, chunks, query) for embedder in c.embedders]
    combine_scores(RRFCombiner(), scores)
end