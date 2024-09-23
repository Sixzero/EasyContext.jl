using SHA, JLD2
using Parameters
using PromptingTools.Experimental.RAGTools: AbstractEmbedder
using PromptingTools: MODEL_EMBEDDING

"""
cache_prefix: The prefix addition to the file being saved.
"""
@kwdef struct CachedBatchEmbedder <: AbstractEmbedder
    embedder::AbstractEmbedder = OpenAIBatchEmbedder()
    cache_dir::String = let
        current_file = @__FILE__
        default_cache_dir = joinpath(dirname(dirname(dirname(current_file))), "cache")
        isdir(default_cache_dir) || mkpath(default_cache_dir)
        default_cache_dir
    end
    cache_prefix::String=""
    truncate_dimension::Union{Int, Nothing}=nothing
end
get_embedder(embedder::CachedBatchEmbedder) = get_embedder(embedder.embedder)
get_embedder_uniq_id(embedder::CachedBatchEmbedder) = get_embedder_uniq_id(embedder.embedder)
get_model_name(embedder::CachedBatchEmbedder) = get_model_name(get_embedder(embedder))

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractString};
        verbose::Bool = true,
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads(),
        kwargs...)
    if isempty(docs)
        verbose && @info "No documents to embed."
        return Matrix{Float32}(undef, 0, 0)
    end
    model = get_model_name(embedder)
    unique_name = get_embedder_uniq_id(embedder)
    cache_prefix, truncate_dimension = embedder.cache_prefix, embedder.truncate_dimension
    
    cache_file = joinpath(embedder.cache_dir, cache_prefix * "embeddings_$(unique_name).jld2")
    cache = isfile(cache_file) ? JLD2.load(cache_file) : Dict{String, Vector{Float32}}()
    
    doc_hashes = [bytes2hex(sha256(doc)) for doc in docs]
    to_embed_indices = findall(i -> !haskey(cache, doc_hashes[i]), eachindex(docs))
    
    if !isempty(to_embed_indices)
        docs_to_embed = docs[to_embed_indices]
        new_embeddings = get_embeddings(embedder.embedder, docs_to_embed;
            verbose, model, truncate_dimension, cost_tracker,
            target_batch_size_length, ntasks, kwargs...)
        
        for (new_idx, doc_idx) in enumerate(to_embed_indices)
            cache[doc_hashes[doc_idx]] = new_embeddings[:, new_idx]
        end
        
        JLD2.save(cache_file, cache)
    end
    
    # Create all_embeddings after potentially updating the cache
    embedding_dim = length(first(values(cache)))
    all_embeddings = zeros(Float32, embedding_dim, length(docs))
    
    for (i, hash) in enumerate(doc_hashes)
        all_embeddings[:, i] = cache[hash]
    end
    
    if verbose
        cached_count = length(docs) - length(to_embed_indices)
        @info "Embedding complete. $cached_count docs from cache, $(length(to_embed_indices)) newly embedded."
        @info "Total cost: \$$(round(cost_tracker[], digits=3))"
    end
   
    return all_embeddings
end
