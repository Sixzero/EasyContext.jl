
using JLD2
using SHA


@kwdef mutable struct CachedLoader{T<:Cacheable,D} <: Cacheable
    loader::T
    cache_dir::String = CACHE_DIR
    memory::Dict{String,D}
end

cache_key(loader::Cacheable, args...)          = @assert false "Unimplemented method for $(typeof(loader))!"
cache_filename(loader::Cacheable, key::String) = @assert false "Unimplemented method for $(typeof(loader))!"

function (cache::CachedLoader)(args...)
    key = cache_key(cache.loader, args...)
    haskey(cache.memory, key) && return cache.memory[key]

    file_path = joinpath(cache.cache_dir, cache_filename(cache.loader, key))
    if isfile(file_path)
        result = deserialize(file_path)
    else
        result = cache.loader(args...)
        serialize(file_path, result)
    end

    cache.memory[key] = result
    return result
end

serialize(file_path::String, data) = JLD2.save(file_path, "data", data)
deserialize(file_path::String)     = JLD2.load(file_path, "data")
