import RAGTools: get_chunks, AbstractEmbedder
import RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import RAGTools: ChunkIndex, AbstractChunker
import ExpressionExplorer
import JuliaSyntax
import JuliaSyntax: @K_str, kind
using Pkg
using ProgressMeter

include("JuliaChunker.jl")
include("PythonChunker.jl")

struct SourceChunker <: AbstractChunker end


function RAG.get_chunks(chunker::SourceChunker,
        items::Vector{<:Any};
        sources::AbstractVector{<:AbstractString} = String[],
        verbose::Bool = false)
    @assert isempty(sources) || length(sources) == length(items) "Length of `sources` must match length of `items` if provided"

    output_chunks = Vector{SourceChunk}()
    output_sources = Vector{eltype(sources)}()
    extras = Vector{Dict{Symbol, String}}()

    progress = Progress(length(items), desc="Collecting chunks: ", showspeed=true)
    
    for (i, item) in enumerate(items)
        if item isa AbstractString && isfile(item)
            # Process individual file
            process_file(chunker, item, isempty(sources) ? item : sources[i], output_chunks, verbose)
        elseif item isa Pkg.API.PackageInfo
            # Process Julia package
            process_package(chunker, item, output_chunks, verbose)
        else
            @warn "Unsupported item type: $(typeof(item))"
        end
        next!(progress)
    end

    return output_chunks
end

function process_file(chunker::SourceChunker, file_path::AbstractString, source::AbstractString, 
                      output_chunks::Vector{SourceChunk}, verbose::Bool)
    if endswith(lowercase(file_path), ".jl")
        julia_chunker = JuliaSourceChunker()
        chunks = get_chunks(julia_chunker, [file_path]; sources=[source], verbose=verbose)
    elseif endswith(lowercase(file_path), ".py")
        python_chunker = PythonSourceChunker()
        chunks = get_chunks(python_chunker, [file_path]; sources=[source], verbose=verbose)
    else
        @warn "Unsupported file type: $file_path"
        return
    end

    append!(output_chunks, chunks)
end

function process_package(chunker::SourceChunker, pkg_info::Pkg.API.PackageInfo, 
                         output_chunks::Vector{SourceChunk}, verbose::Bool)
    pkg_path = pkg_info.source
    if isnothing(pkg_path)
        @warn "Package $(pkg_info.name) has no source path"
        return
    end

    # Find the main entry point of the package (usually src/PackageName.jl)
    main_file = joinpath(pkg_path, "src", "$(pkg_info.name).jl")
    if !isfile(main_file)
        @warn "Main file for package $(pkg_info.name) not found at $main_file"
        return
    end
    
    # Process the main file and its includes
    file_module_map = Dict{String, Vector{String}}()
    initial_module_stack = String[] # the src/pkgname.jl will add the pkg's initial pkgname
    process_julia_file_recursively(main_file, initial_module_stack, file_module_map)
    
    julia_chunker = JuliaSourceChunker()

    for (file, modules) in file_module_map
        chunks = get_chunks(julia_chunker, [file]; sources=[file], verbose=verbose, modules=modules)
        append!(output_chunks, chunks)
    end
end

function process_node(node::JuliaSyntax.SyntaxNode, module_stack::Vector{String}, result::Dict{String, Vector{String}}, file_path::String)
    for child in JuliaSyntax.children(node)
        if JuliaSyntax.kind(child) == K"call"
            call_children = JuliaSyntax.children(child)
            if length(call_children) >= 1
                func = call_children[1]
                if JuliaSyntax.kind(func) == K"Identifier" && (func.val == :include || func.val == :includet)
                    if length(call_children) >= 2
                        include_arg = call_children[2]
                        if JuliaSyntax.kind(include_arg) == K"string"
                            include_path = JuliaSyntax.sourcetext(include_arg)
                            # Remove surrounding quotes
                            include_path = strip(include_path, '"')
                            # Construct the full path
                            full_include_path = normpath(joinpath(dirname(file_path), include_path))
                            if isfile(full_include_path)
                                # Process the included file
                                process_julia_file_recursively(full_include_path, module_stack, result)
                            else
                                @warn "Included file not found: $full_include_path"
                            end
                        end
                    end
                end
            end
        elseif JuliaSyntax.kind(child) == K"module"
            module_children = JuliaSyntax.children(child)
            if length(module_children) >= 1
                module_name = module_children[1].val
                if module_name == nothing
                    @warn "Unknown module format: $child # TODO handle eventually. $(module_children)"
                    continue
                end
                new_module_stack = [module_stack; String(module_name)]
                if length(module_children) >= 2
                    process_node(module_children[2], new_module_stack, result, file_path)
                end
            end
        else
            process_node(child, module_stack, result, file_path)
        end
    end
end

function process_julia_file_recursively(file_path::String, module_stack::Vector{String}, result::Dict{String, Vector{String}})
    if haskey(result, file_path)
        return  # File has already been processed
    end
    
    result[file_path] = module_stack
    
    open(file_path, "r") do file
        content = read(file, String)
        ast = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, content, ignore_warnings=true)
        process_node(ast, module_stack, result, file_path)
    end
end

# is there an alternative to unicode safe indexing?
function safe_substring2(s, from, to)
    start = firstindex(s)
    stop = lastindex(s)
    
    from_index = min(max(start, from), stop)
    to_index = min(max(from_index, to), stop)
    
    from_index = nextind(s, from_index - 1)
    to_index = prevind(s, to_index + 1)
    
    return s[from_index:to_index]
end
function is_include_call(node::JuliaSyntax.SyntaxNode)
    children = JuliaSyntax.children(node)
    return length(children) >= 1 && 
           children[1].val == :include
end

function get_include_file(node::JuliaSyntax.SyntaxNode)
    children = JuliaSyntax.children(node)
    if length(children) >= 2 && kind(children[2]) == K"string"
        string_content = string(children[2])
        # Use regex to extract the file name
        m = match(r"\"(.+?)\"", string_content)
        if m !== nothing # TODO later on somehow try to access the value from the SyntaxNode
            return m.captures[1]
        else
            @warn "Could not extract file name from string: $string_content"
            return ""
        end
    else
        @warn "Unexpected include call structure"
        return ""
    end
end

