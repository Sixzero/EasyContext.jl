@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, :all, or :minimal
end

function (loader::JuliaLoader)(chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope)
    chunks, sources = RAGTools.get_chunks(chunker, pkg_infos)
    return OrderedDict(zip(sources, String.(chunks)))
end

function get_package_infos(scope::Symbol)
    all_dependencies = Pkg.dependencies()

    if scope == :installed
        return [info for (uuid, info) in all_dependencies if info.is_direct_dep==true && info.version !== nothing]
    elseif scope == :dependencies
        return collect(values(all_dependencies))
    elseif scope == :all
        return collect(values(all_dependencies))
    elseif scope == :minimal
        return [info for (uuid, info) in all_dependencies if info.name in ["Base64"]]
    else
        error("Invalid package scope: $scope")
    end
end

function cache_key(loader::JuliaLoader, chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope)
    code = bytes2hex(sha256("JuliaLoader_$(loader.package_scope)_$(hash_pkg_infos(pkg_infos))_$(hash("$CHUNKER"))"))
    code
end

function hash_pkg_infos(pkg_infos)
    fast_cache_key(get_pkg_unique_key, pkg_infos)
end

function get_pkg_unique_key(loader::Pkg.API.PackageInfo) 
    return string(loader.name, loader.version)
end
function cache_filename(loader::JuliaLoader, key::String)
    return "julia_loader_file_$(loader.package_scope)_$key.jld2"
end
