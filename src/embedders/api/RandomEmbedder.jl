using Random
using LinearAlgebra

"""
    RandomEmbedder <: AbstractEasyEmbedder

A struct for generating random embedding vectors for testing and precompilation.

# Fields
- `dimensions::Int`: The dimensionality of the embedding vectors (default: 1536).
- `rng::AbstractRNG`: The random number generator to use.
- `model::String`: A dummy model name for compatibility.
- `verbose::Bool`: Whether to print verbose output.
"""
@kwdef mutable struct RandomEmbedder <: AbstractEasyEmbedder
    dimensions::Int = 1536
    rng::AbstractRNG = Random.default_rng()
    model::String = "random-embedder"
    verbose::Bool = true
end

function get_embeddings(embedder::RandomEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    # Pre-allocate the result matrix directly
    n_docs = length(docs)
    result = Matrix{Float32}(undef, embedder.dimensions, n_docs)
    
    # Fill and normalize in a single pass
    for i in 1:n_docs
        # Generate random values directly into the result matrix
        rand!(embedder.rng, view(result, :, i))
        
        # Normalize the column in-place
        normalize!(view(result, :, i))
    end
    
    verbose && @info "Generated $n_docs random embeddings with dimensions $(embedder.dimensions)"
    
    return result
end

"""
    create_random_embedder(; dimensions=1536, seed=nothing, verbose=true, cache_prefix="")

Create a RandomEmbedder with specified parameters.

# Arguments
- `dimensions::Int`: The dimensionality of the embedding vectors.
- `seed::Union{Nothing, Integer}`: Optional seed for the random number generator.
- `verbose::Bool`: Whether to print verbose output.
- `cache_prefix::String`: If non-empty, wraps the embedder in a CachedBatchEmbedder.

# Returns
- `AbstractEasyEmbedder`: A RandomEmbedder or CachedBatchEmbedder containing a RandomEmbedder.
"""
function create_random_embedder(;
    dimensions::Int = 1024,
    seed::Union{Nothing, Integer} = nothing,
    verbose::Bool = true,
    cache_prefix::String = "random_embedder"
)
    rng = isnothing(seed) ? Random.default_rng() : Random.MersenneTwister(seed)
    random_embedder = RandomEmbedder(; dimensions, rng, verbose)
    CachedBatchEmbedder(; embedder=random_embedder, cache_prefix, verbose)
end

# Implement humanize method
humanize(e::RandomEmbedder) = "Random:$(e.dimensions)d"

export create_random_embedder
