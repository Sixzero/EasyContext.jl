@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
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
    elseif scope ∈ (:dependencies, :all)
        return collect(values(all_dependencies))
    else
        error("Invalid package scope: $scope")
    end
end


# Example of overloading cache_key for a specific loader (e.g., JuliaLoader)
function cache_key(loader::JuliaLoader, chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope)
    code = bytes2hex(sha256("JuliaLoader_$(hash_pkg_infos(pkg_infos))_$(hash("$CHUNKER"))"))
    code
end


function hash_pkg_infos(pkg_infos)
    pkg_strings = sort([string(info.name, info.version) for info in pkg_infos])
    return bytes2hex(sha256(join(pkg_strings, ",")))
end

# Example of overloading cache_filename for a specific loader (e.g., JuliaLoader)
function cache_filename(loader::JuliaLoader, key::String)
    return "julia_loader_file_$(loader.package_scope)_$key.jld2"
end
