abstract type MultiEmbedderCombiner <: RAGTools.AbstractEmbedder end

struct MaxScoreCombiner <: CombinationMethod end
struct WeightedCombiner <: CombinationMethod 
    weights::Vector{Float64}
end
struct RRFCombiner <: CombinationMethod end

function combine_scores(::MaxScoreCombiner, scores::AbstractVector{<:AbstractVector})
    n = length(first(scores))
    [maximum(s[i] for s in scores) for i in 1:n]
end

function combine_scores(c::WeightedCombiner, scores::AbstractVector{<:AbstractVector})
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
    embedders::Vector{RAGTools.AbstractEmbedder}
end

function get_score(c::WeighterEmbedder, chunks, query; kwargs...)
    scores = [get_score(embedder, chunks, query; kwargs...) for embedder in c.embedders]
    combine_scores(WeightedCombiner(c.weights), scores)
end

struct MaxScoreEmbedder <: MultiEmbedderCombiner
    embedders::AbstractVector{RAGTools.AbstractEmbedder}
end

function get_score(c::MaxScoreEmbedder, chunks, query; kwargs...)
    scores = [get_score(embedder, chunks, query; kwargs...) for embedder in c.embedders]
    combine_scores(MaxScoreCombiner(), scores)
end

struct RRFScoreEmbedder <: MultiEmbedderCombiner
    embedders::AbstractVector{RAGTools.AbstractEmbedder}
end

function get_score(c::RRFScoreEmbedder, chunks, query; kwargs...)
    scores = [get_score(embedder, chunks, query; kwargs...) for embedder in c.embedders]
    combine_scores(RRFCombiner(), scores)
end

struct MeanScoreEmbedder <: MultiEmbedderCombiner
    embedders::AbstractVector{RAGTools.AbstractEmbedder}
end

function get_score(c::MeanScoreEmbedder, chunks, query; kwargs...)
    scores = [get_score(embedder, chunks, query; kwargs...) for embedder in c.embedders]
    n = length(first(scores))
    [sum(s[i] for s in scores)/length(scores) for i in 1:n]
end

# Update humanize methods to cascade
humanize(c::MaxScoreEmbedder) = "max[$(join(humanize.(c.embedders), ", "))]"
humanize(c::RRFScoreEmbedder) = "rrf[$(join(humanize.(c.embedders), ", "))]"
humanize(c::MeanScoreEmbedder) = "mean[$(join(humanize.(c.embedders), ", "))]"
humanize(c::WeighterEmbedder) = "weighted($(c.weights))[$(join(humanize.(c.embedders), ", "))]"