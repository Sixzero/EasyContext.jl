@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, :all, or :minimal
end

function (loader::JuliaLoader)(chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope)
    chunks, sources = RAGTools.get_chunks(chunker, pkg_infos)
    return OrderedDict(zip(sources, String.(chunks)))
end

function get_package_infos(scope::Symbol)
    global_env_path = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)", "Project.toml")
    global_env = Pkg.Types.EnvCache(global_env_path)
    all_dependencies = Pkg.dependencies(global_env)
    # scope == :installed && return collect(values(simplified_dependencies(global_env_path))) # this is 0.0002s while running the whole Pkg.dependencies is 0.02s if not more with more packages. But it has extremely more information than we need.
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
function get_pkg_unique_key(loader::SimplePackageInfo) 
    return string(loader.name, loader.version)
end
function cache_filename(loader::JuliaLoader, key::String)
    return "julia_loader_file_$(loader.package_scope)_$key.jld2"
end
