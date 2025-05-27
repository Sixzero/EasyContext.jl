@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, :all, or :minimal
    excluded_packages::Vector{String} = String[]  # New field for excluded packages
end

function RAGTools.get_chunks(loader::JuliaLoader, chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope, loader.excluded_packages)
    chunks = RAGTools.get_chunks(chunker, pkg_infos)
    return chunks
end

function get_package_infos(scope::Symbol, excluded_packages::Vector{String})
    global_env_path = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)", "Project.toml")
    global_env = Pkg.Types.EnvCache(global_env_path)
    all_dependencies = Pkg.dependencies(global_env)

    pkg_infos = if scope == :installed 
        [info for (uuid, info) in all_dependencies if info.is_direct_dep==true && info.version !== nothing]
    elseif scope == :dependencies || scope == :all
        collect(values(all_dependencies))
    elseif scope == :minimal
        [info for (uuid, info) in all_dependencies if info.name in ["Base64"]]
    else
        warn("Invalid package scope: $scope")
        []
    end

    return [info for info in pkg_infos if info.name ∉ excluded_packages]
end

function cache_key(loader::JuliaLoader, chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope, loader.excluded_packages)
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
