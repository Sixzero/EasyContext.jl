@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
end

function (loader::JuliaLoader)(chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    pkg_infos = get_package_infos(loader.package_scope)
    chunks, sources = RAGTools.get_chunks(chunker, pkg_infos)
    return OrderedDict(zip(sources, chunks))
end

function get_context(context::JuliaLoader, question::String, ai_state=nothing, shell_results=nothing)
    result = context(question)
    return result
end

function get_package_infos(scope::Symbol)
    installed_packages = Pkg.installed()
    all_dependencies = Pkg.dependencies()

    if scope == :installed
        return [info for (uuid, info) in all_dependencies if info.name in keys(installed_packages)]
    elseif scope ∈ (:dependencies, :all)
        return collect(values(all_dependencies))
    else
        error("Invalid package scope: $scope")
    end
end

function cut_history!(processor::JuliaLoader, keep::Int)
    # Implement if needed
end
