@kwdef mutable struct JuliaPackageContext <: AbstractContextProcessor
    context_node::ContextNode = ContextNode(title="FunctionsRelevant", element="Func")
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
    index_builder::AbstractIndexBuilder = MultiIndexBuilder()
end

function get_context(context::JuliaPackageContext, question::String, ai_state=nothing, shell_results=nothing)
    pkg_infos = get_package_infos(context.package_scope)
    result = get_context(context.index_builder, question; data=pkg_infos)

    add_or_update_source!(context.context_node, result.sources, result.context)

    return context.context_node
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
    cut_history!(processor.context_node, keep)
end
