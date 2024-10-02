@kwdef mutable struct JuliaLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
    cache::Union{Nothing, OrderedDict{String,String}} = nothing  # TODO cache should be modular!
    last_pkg_hash::String = ""                                              # this is ALSO only cache!! coudl be the filename
end

function (context::JuliaLoader)(chunker::CHUNKER) where {CHUNKER <: AbstractChunker}
    return get_cached_chunks(context, chunker)
end

function get_cached_chunks(context::JuliaLoader, chunker)
    pkg_infos = get_package_infos(context.package_scope)
    current_hash = hash_pkg_infos(pkg_infos)
    
    if context.last_pkg_hash == current_hash && !isnothing(context.cache)
        return context.cache
    end
    
    cache_file = joinpath(CACHE_DIR, "julia_package_context_$(context.package_scope)_$(current_hash)v5.jld2")
    
    if isfile(cache_file)
        cached_data = JLD2.load(cache_file)
        context.cache = cached_data
        context.last_pkg_hash = current_hash
        return context.cache
    end
    
    _chunks, _sources = RAGTools.get_chunks(chunker, pkg_infos)
    chunks, sources = String.(_chunks), String.(_sources)
    context.cache = OrderedDict{String,String}(zip(sources, chunks))
    
    JLD2.save(cache_file, context.cache)
    
    context.last_pkg_hash = current_hash
    
    return context.cache
end

function hash_pkg_infos(pkg_infos)
    # Create a stable representation of package info for hashing
    pkg_strings = sort([string(info.name, info.version) for info in pkg_infos])
    return bytes2hex(sha256(join(pkg_strings, ",")))
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
