@kwdef mutable struct JuliaPackageContext <: AbstractContextProcessor
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
    chunker::GolemSourceChunker=GolemSourceChunker()
end

function (context::JuliaPackageContext)(question::String)
    pkg_infos = get_package_infos(context.package_scope)
    chunks, sources = RAGTools.get_chunks(context.chunker, pkg_infos)
    return RAGResult(SourceChunk(sources, chunks), question)
end

function get_context(context::JuliaPackageContext, question::String, ai_state=nothing, shell_results=nothing)
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

function AISH.cut_history!(processor::JuliaPackageContext, keep::Int)
    # Implement if needed
end
