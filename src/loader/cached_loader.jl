
using JLD2
using SHA

abstract type AbstractLoader end

@kwdef struct CachedLoader{L<:AbstractLoader} <: AbstractLoader
    loader::L
    cache_dir::String = joinpath(dirname(dirname(@__DIR__)), "cache")
end

# Default hash function (can be overloaded for specific loaders)
function cache_key(loader::AbstractLoader, args...)
    return bytes2hex(sha256("$(typeof(loader))_$(hash(loader))_$(hash(args))"))
end

# Default cache filename function (can be overloaded for specific loaders)
function cache_filename(loader::AbstractLoader, key::String)
    return "loader_cache_$key.jld2"
end

function (cached_loader::CachedLoader)(args...)
    loader = cached_loader.loader
    key = cache_key(loader, args...)
    filename = joinpath(cached_loader.cache_dir, cache_filename(loader, key))
    
    if isfile(filename)
        cached_data = JLD2.load(filename)
        if cached_data["key"] == key
            return cached_data["value"]
        end
    end
    
    result = loader(args...)
    
    mkpath(cached_loader.cache_dir)
    JLD2.save(filename, "key" => key, "value" => result)
    
    return result
end

# Example of overloading cache_key for a specific loader (e.g., JuliaLoader)
function cache_key(loader::JuliaLoader, args...)
    pkg_infos = get_package_infos(loader.package_scope)
    return bytes2hex(sha256("JuliaLoader_$(hash_pkg_infos(pkg_infos))_$(hash(args))"))
end


function hash_pkg_infos(pkg_infos)
    pkg_strings = sort([string(info.name, info.version) for info in pkg_infos])
    return bytes2hex(sha256(join(pkg_strings, ",")))
end

# Example of overloading cache_filename for a specific loader (e.g., JuliaLoader)
function cache_filename(loader::JuliaLoader, key::String)
    return "julia_loader_cache_$(loader.package_scope)_$key.jld2"
end

# You can add more specific cache_key and cache_filename implementations for other loaders here


