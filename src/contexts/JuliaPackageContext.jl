@kwdef mutable struct JuliaPackageContext <: AbstractContextProcessor
    context_node::ContextNode = ContextNode(title="Existing functions in other libraries")
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
    multi_index_context::MultiIndexContext = MultiIndexContext()
    force_rebuild::Bool = false
    verbose::Bool = true
end

function get_context(processor::JuliaPackageContext, question::String, ai_state=nothing, shell_results=nothing)
    # Initialize or rebuild the index if necessary
    if isnothing(processor.multi_index_context.index) || processor.force_rebuild
        pkg_infos = get_package_infos(processor.package_scope)
        index, finders = build_index(processor.multi_index_context.index_builder, pkg_infos)
        processor.multi_index_context.index = index
    end
    
    # Use the MultiIndexContext to get relevant information
    result = get_context(processor.multi_index_context, question; force_rebuild=processor.force_rebuild, suppress_output=!processor.verbose)
    
    add_or_update_source!(processor.context_node, result.sources, result.contexts)
    
    return processor.context_node
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
