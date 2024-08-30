import PromptingTools.Experimental.RAGTools: get_chunks, AbstractEmbedder
import PromptingTools.Experimental.RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import PromptingTools.Experimental.RAGTools: ChunkIndex, AbstractChunker
import ExpressionExplorer
using JuliaSyntax
using Pkg

include("GolemUtils.jl")
include("GolemJuliaChunker.jl")
include("GolemPythonChunker.jl")

struct GolemSourceChunker <: AbstractChunker end

function get_chunks(chunker::GolemSourceChunker,
        files_or_packages::Vector{<:AbstractString};
        sources::AbstractVector{<:AbstractString} = files_or_packages,
        verbose::Bool = true)

    @assert (length(sources) == length(files_or_packages)) "Length of `sources` must match length of `files_or_packages`"

    output_chunks = Vector{SubString{String}}()
    output_sources = Vector{eltype(sources)}()

    for i in eachindex(files_or_packages, sources)
        item = files_or_packages[i]
        
        if isfile(item)
            # Process individual file
            process_file(chunker, item, sources[i], output_chunks, output_sources, verbose)
        else
            # Assume it's a package name
            process_package(chunker, item, output_chunks, output_sources, verbose)
        end
    end

    return output_chunks, output_sources
end

function process_file(chunker::GolemSourceChunker, file_path::AbstractString, source::AbstractString, 
                      output_chunks::Vector{SubString{String}}, output_sources::Vector, verbose::Bool)
    if endswith(lowercase(file_path), ".jl")
        julia_chunker = JuliaSourceChunker()
        chunks, src = get_chunks(julia_chunker, [file_path]; sources=[source], verbose=verbose)
    elseif endswith(lowercase(file_path), ".py")
        python_chunker = PythonSourceChunker()
        chunks, src = get_chunks(python_chunker, [file_path]; sources=[source], verbose=verbose)
    else
        @warn "Unsupported file type: $file_path"
        return
    end

    append!(output_chunks, chunks)
    append!(output_sources, src)
end

function process_package(chunker::GolemSourceChunker, package_name::AbstractString, 
                         output_chunks::Vector{SubString{String}}, output_sources::Vector, verbose::Bool)
    # Check if the input contains path separators
    if occursin(r"/|\\\\", package_name)
        verbose && @info "Skipping '$package_name' as it contains path separators and is likely not a package name."
        return
    end
    # Try as Julia package first
    julia_files = process_julia_package(package_name, verbose)
    
    if !isempty(julia_files)
        verbose && @info "Processing Julia package: $package_name"
        for (file, modules) in julia_files
            process_julia_file(chunker, file, modules, output_chunks, output_sources, verbose)
        end
    else
        # If not a Julia package, try as Python package
        python_files = get_python_package_files(package_name)
        
        if !isempty(python_files)
            verbose && @info "Processing Python package: $package_name"
            for file in python_files
                process_file(chunker, file, file, output_chunks, output_sources, verbose)
            end
        else
            @warn "Unable to process $package_name as either a Julia or Python package"
        end
    end
end

function process_julia_package(package_name::String, verbose::Bool)
    # First, check if the package is installed in the current project
    pkg_path = nothing
    if haskey(Pkg.project().dependencies, package_name)
        pkg_info = Pkg.project().dependencies[package_name]
        pkg_path = pkg_info.path
        if isnothing(pkg_path)
            pkg_path = joinpath(Pkg.devdir(), package_name)
        end
    else
        # If not in the current project, check if it's installed system-wide
        pkg_path = try
            dirname(dirname(Base.find_package(package_name)))
        catch
            nothing
        end
    end
    
    if isnothing(pkg_path) || !isdir(pkg_path)
        @warn "Package $package_name not found or not a valid directory"
        return Dict{String, Vector{String}}()
    end
    
    # Find the main entry point of the package (usually src/PackageName.jl)
    main_file = joinpath(pkg_path, "src", "$package_name.jl")
    if !isfile(main_file)
        @warn "Main file for package $package_name not found at $main_file"
        return Dict{String, Vector{String}}()
    end
    
    # Process the main file and its includes
    return process_julia_file_recursively(main_file, [package_name])
end

function process_julia_file_recursively(file_path::String, module_stack::Vector{String})
    result = Dict{String, Vector{String}}()
    result[file_path] = copy(module_stack)
    
    open(file_path, "r") do file
        for line in eachline(file)
            if startswith(strip(line), "include(")
                included_file = match(r"include\([\"'](.*?)[\"']\)", line).captures[1]
                included_path = joinpath(dirname(file_path), included_file)
                merge!(result, process_julia_file_recursively(included_path, module_stack))
            elseif startswith(strip(line), "module ")
                module_name = match(r"module\s+(\w+)", line).captures[1]
                push!(module_stack, module_name)
                # Process the rest of the file with the updated module stack
                merge!(result, process_julia_file_recursively(file_path, module_stack))
                pop!(module_stack)
                break  # Stop processing this file after the module definition
            end
        end
    end
    
    return result
end

function process_julia_file(chunker::GolemSourceChunker, file_path::String, modules::Vector{String}, 
                            output_chunks::Vector{SubString{String}}, output_sources::Vector, verbose::Bool)
    julia_chunker = JuliaSourceChunker()
    chunks, _ = get_chunks(julia_chunker, [file_path]; sources=[file_path], verbose=verbose)
    
    module_info = join(modules, ".")
    for chunk in chunks
        push!(output_chunks, chunk)
        push!(output_sources, "$file_path [Module: $module_info]")
    end
end

function get_python_package_files(package_name::String)
    try
        # This assumes the Python package is installed and importable
        cmd = `python -c "import $(package_name), os, sys; print(os.path.dirname(sys.modules['$(package_name)'].__file__))"`
        pkg_path = strip(read(cmd, String))
        
        python_files = String[]
        for (root, _, files) in walkdir(pkg_path)
            for file in files
                if endswith(file, ".py")
                    push!(python_files, joinpath(root, file))
                end
            end
        end
        return python_files
    catch e
        @warn "Error processing Python package $package_name: $e"
        return String[]
    end
end

