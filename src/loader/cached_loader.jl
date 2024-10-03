
using JLD2
using SHA


@kwdef mutable struct CachedLoader{T<:Cacheable} <: Cacheable
    loader::T
    cache_dir::String = CACHE_DIR
    in_memory_key::String = ""
    in_memory_value::Any  = nothing
end

cache_key(loader::Cacheable, args...)          = @assert false "Unimplemented method for $(typeof(loader))!"
cache_filename(loader::Cacheable, key::String) = @assert false "Unimplemented method for $(typeof(loader))!"

function (cached_loader::CachedLoader)(args...)
    loader = cached_loader.loader
    key = cache_key(loader, args...)
    
    key == cached_loader.in_memory_key && return cached_loader.in_memory_value
    
    filename = joinpath(cached_loader.cache_dir, cache_filename(loader, key))
    
    if isfile(filename)
        result = JLD2.load(filename, "value")
        cached_loader.in_memory_key, cached_loader.in_memory_value = key, result
        return result
    end
    
    result = loader(args...)
    
    JLD2.save(filename, value=result)
    cached_loader.in_memory_key, cached_loader.in_memory_value = key, result
    
    return result
end


