using SHA, JLD2
using Parameters
using PromptingTools.Experimental.RAGTools: BatchEmbedder
using PromptingTools: MODEL_EMBEDDING

@kwdef struct CachedBatchEmbedder <: AbstractEmbedder
    embedder::BatchEmbedder = BatchEmbedder()
    cache_dir::String = let
        current_file = @__FILE__
        default_cache_dir = joinpath(dirname(dirname(current_file)), "cache")
        isdir(default_cache_dir) || mkpath(default_cache_dir)
        default_cache_dir
    end
end

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractString};
        verbose::Bool = true,
        model::AbstractString = MODEL_EMBEDDING,
        truncate_dimension::Union{Int, Nothing} = nothing,
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads(),
        kwargs...)
    @show model
    # Create cache filename based on the model
    cache_file = joinpath(embedder.cache_dir, "embeddings_$(model).jld2")
    
    # Load or create cache
    if isfile(cache_file)
        cache = JLD2.load(cache_file)
    else
        cache = Dict{String, Vector{Float32}}()
    end
    
    # Identify which docs need embedding
    docs_to_embed = String[]
    doc_hashes = String[]
    cached_embeddings = Vector{Float32}[]
    
    for doc in docs
        doc_hash = bytes2hex(sha256(doc))
        if haskey(cache, doc_hash)
            push!(cached_embeddings, cache[doc_hash])
        else
            push!(docs_to_embed, doc)
            push!(doc_hashes, doc_hash)
        end
    end
    
    # Embed uncached docs
    if !isempty(docs_to_embed)
        new_embeddings = get_embeddings(embedder.embedder, docs_to_embed;
            verbose, model, truncate_dimension, cost_tracker,
            target_batch_size_length, ntasks, kwargs...)
        
        # Update cache
        for (doc_hash, embedding) in zip(doc_hashes, eachcol(new_embeddings))
            cache[doc_hash] = embedding
        end
        
        # Save updated cache
        JLD2.save(cache_file, cache)
        
        # Combine cached and new embeddings
        all_embeddings = hcat(stack(cached_embeddings, dims=2), new_embeddings)
    else
        all_embeddings = stack(cached_embeddings, dims=2)
    end
    
    verbose && @info "Embedding complete. $(length(docs) - length(docs_to_embed)) docs from cache, $(length(docs_to_embed)) newly embedded."
    verbose && @info "Total cost: \$$(round(cost_tracker[], digits=3))"
   
    return all_embeddings
end