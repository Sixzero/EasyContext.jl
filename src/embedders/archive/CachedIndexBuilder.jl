using JLD2, SHA

@kwdef mutable struct CachedBatchEmbedder{T<:AbstractIndexBuilder} <: AbstractIndexBuilder
    builder::T
    cache_dir::String="cache"
end

function CachedBatchEmbedder(builder::T; cache_dir::String="cache") where T<:AbstractIndexBuilder
    return CachedBatchEmbedder{T}(builder, cache_dir)
end

function fast_cache_key(chunks::OrderedDict{String, String})
    fast_cache_key(keys(chunks))
end

function fast_cache_key(keys::AbstractSet)
    if isempty(keys)
        return string(zero(UInt64))  # Return a zero hash for empty input
    end
    
    # Combine hashes of all keys
    combined_hash = reduce(xor, hash(key) for key in keys)
    
    return string(combined_hash, base=16, pad=16)  # Convert to 16-digit hexadecimal string
end

function fast_cache_key(fn::Function, keys)
    if isempty(keys)
        return string(zero(UInt64))  # Return a zero hash for empty input
    end

    # Combine hashes of all keys
    combined_hash = reduce(xor, hash(fn(key)) for key in keys)

    return string(combined_hash, base=16, pad=16)
end

function get_index(cached_builder::CachedBatchEmbedder, chunks::OrderedDict{String, String}; 
                   cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false, force_rebuild=false)
    cache_key = fast_cache_key(chunks)
    
    # Create a centralized cache directory within EasyContext.jl
    pkg_cache_dir = joinpath(dirname(@__DIR__), "..", cached_builder.cache_dir, "index_cache")
    mkpath(pkg_cache_dir)
    
    cache_file = joinpath(pkg_cache_dir, "index_$(cache_key).jld2")

    if !force_rebuild && isfile(cache_file)
        verbose && @info "Loading cached index from $cache_file"
        return JLD2.load(cache_file, "index")
    else
        verbose && @info "Building new index"
        index = get_index(cached_builder.builder, chunks; cost_tracker=cost_tracker, verbose=verbose)
        JLD2.save(cache_file, "index", index)
        return index
    end
end

# Delegate other methods to the wrapped builder
get_embedder(cached_builder::CachedBatchEmbedder) = get_embedder(cached_builder.builder)
get_finder(cached_builder::CachedBatchEmbedder) = get_finder(cached_builder.builder)
get_processor(cached_builder::CachedBatchEmbedder) = get_processor(cached_builder.builder)

# Implement the call method to delegate to the wrapped builder
function similarity_search(cached_builder::CachedBatchEmbedder, index, query::AbstractString)
    similarity_search(cached_builder.builder, index, query)
end
