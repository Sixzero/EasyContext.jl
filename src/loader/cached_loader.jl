
using JLD2
using SHA


@kwdef mutable struct CachedLoader{T,D} <: Cacheable
    loader::T
    cache_dir::String = CACHE_DIR
    memory::Dict{String,D}
end

cache_key(loader::Cacheable, args...)          = @assert false "Unimplemented method for $(typeof(loader))!"
cache_filename(loader::Cacheable, key::String) = @assert false "Unimplemented method for $(typeof(loader))!"

# Generic caching mechanism for any operation
function cached_operation(cache::CachedLoader, operation::Function, args...; kwargs...)
    key = cache_key(cache.loader, args...; kwargs...)
    haskey(cache.memory, key) && return cache.memory[key]

    filename = cache_filename(cache.loader, key)
    file_path = joinpath(cache.cache_dir, filename)
    if isfile(file_path)
        result = deserialize(file_path)
    else
        result = operation(cache.loader, args...; kwargs...)
        serialize(file_path, result)
    end

    cache.memory[key] = result
    return result
end
# Specific operations using the generic mechanism
RAG.get_chunks(cache::CachedLoader, args...) = cached_operation(cache, RAG.get_chunks, args...)
get_score(cache::CachedLoader, args...; kwargs...) = cached_operation(cache, get_score, args...; kwargs...)


serialize(file_path::String, data) = JLD2.save(file_path, "data", data)
deserialize(file_path::String)     = JLD2.load(file_path, "data")

# Utility functions for generating cache keys
function fast_cache_key(chunks::OrderedDict{String, String})
    fast_cache_key(keys(chunks))
end
function fast_cache_key(chunks::Vector{T}) where T
    # Pass get_source as a function and chunks as the iterator
    fast_cache_key(get_source, chunks)
end

function fast_cache_key(keys::AbstractSet)
    if isempty(keys)
        return string(zero(UInt64))  # Return a zero hash for empty input
    end
    
    # Combine hashes of all keys
    combined_hash = reduce(xor, Base.Generator(hash, items))
    
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