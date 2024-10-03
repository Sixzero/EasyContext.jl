
using JLD2
using SHA

abstract type AbstractLoader end

@kwdef struct CachedLoader{L<:AbstractLoader} <: AbstractLoader
    loader::L
    cache_dir::String = CACHE_DIR
end

cache_key(loader::AbstractLoader, args...) = @assert false "Unimplemented method for $(typeof(loader))!"
cache_filename(loader::AbstractLoader, key::String) = @assert false "Unimplemented method for $(typeof(loader))!"

function (cached_loader::CachedLoader)(args...)
    loader   = cached_loader.loader
    key      = cache_key(loader, args...)
    filename = joinpath(cached_loader.cache_dir, cache_filename(loader, key))
    
    if isfile(filename)
        return JLD2.load(filename, "result")
    end
    
    result = loader(args...)
    
    JLD2.save(filename, "result" => result)
    
    return result
end


