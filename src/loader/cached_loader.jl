
using JLD2
using SHA

abstract type Cacheable end

@kwdef mutable struct CachedLoader{T<:Cacheable} <: Cacheable
    loader::T
    cache_dir::String = CACHE_DIR
    in_memory_key::String = ""
    in_memory_value::Any = nothing
end

cache_key(loader::Cacheable, args...)          = @assert false "Unimplemented method for $(typeof(loader))!"
cache_filename(loader::Cacheable, key::String) = @assert false "Unimplemented method for $(typeof(loader))!"

function (cached_loader::CachedLoader)(args...)
    loader = cached_loader.loader
    key = cache_key(loader, args...)
    
    # Check if the key matches the in-memory key
    if key == cached_loader.in_memory_key
        return cached_loader.in_memory_value
    end
    
    filename = joinpath(cached_loader.cache_dir, cache_filename(loader, key))
    
    if isfile(filename)
        result = JLD2.load(filename, "value")
        # Update in-memory cache
        cached_loader.in_memory_key = key
        cached_loader.in_memory_value = result
        return result
    end
    
    result = loader(args...)
    
    # Save to file
    JLD2.save(filename, "value" => result)
    
    # Update in-memory cache
    cached_loader.in_memory_key = key
    cached_loader.in_memory_value = result
    
    return result
end


