import RAGTools: AbstractEmbedder
import RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import RAGTools: ChunkIndex, AbstractChunker
import ExpressionExplorer
import PromptingTools
const RAG = RAGTools

@kwdef struct PythonSourceChunk
    name::Symbol
    signature_hash::Union{UInt64,Nothing} = nothing
    references::Vector{Symbol} = Symbol[]
    start_line_code::Int
    end_line_code::Int
    start_line_docs::Int = 0
    end_line_docs::Int = 0
    file_path::String
    is_function::Bool = false
    chunk::Union{String,Nothing} = nothing
    import_path::Vector{String} = String[] # Renamed from module_stack
end

@kwdef struct PythonSourceChunker <: AbstractChunker
    include_import_info::Bool=true # Renamed from include_module_info
end

file_path_lineno(def::PythonSourceChunk) = "$(def.file_path):$(def.start_line_code)"
file_path(def::PythonSourceChunk) = def.file_path
name_with_signature(def::PythonSourceChunk) = "$(def.name):$(def.signature_hash)"

function RAG.get_chunks(chunker::PythonSourceChunker,
        files_or_docs::Vector{<:AbstractString};
        sources::AbstractVector{<:AbstractString} = files_or_docs,
        verbose::Bool = true, import_paths::Vector{String}=String[])

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"

    output_chunks = Vector{SubString{String}}()
    output_sources = Vector{eltype(sources)}()

    for (file, source) in zip(files_or_docs, sources)
        defs = process_py_file(file, import_paths, verbose)
        chunks = [create_chunk(def, chunker.include_import_info) for def in defs]
        # chunks .|> println
        
        @assert all(!isempty, chunks) "Chunks must not be empty. The following are empty: $(findall(isempty, chunks))"
    
        append!(output_chunks, chunks)
        append!(output_sources, ["$(file_path_lineno(def)) $(join(def.import_path, "."))" for def in defs])
    end

    return output_chunks, output_sources
end

function create_chunk(def::PythonSourceChunk, include_import_info::Bool)
    header = "$(def.file_path):$(def.start_line_code)"
    import_info = if include_import_info && !isempty(def.import_path)
        "\n# from $(join(def.import_path, ".")) import $(def.name)"
    else
        ""
    end
    return "$header$import_info\n$(def.chunk)"
end

function process_py_file(file_path, import_paths::Vector{String}, verbose::Bool=true)
    verbose && @info "Processing Python file: $file_path"
    s = read(file_path, String)
    lines = split(s, '\n')
    defs = source_explorer(lines; file_path=home_abrev(file_path), import_path=import_paths, verbose)
    defs
end

function source_explorer(lines::AbstractVector{<:AbstractString};
    file_path::AbstractString, source_defs=PythonSourceChunk[], import_path=String[], verbose=false)

    current_line = 1
    total_lines = length(lines)

    while current_line <= total_lines
        line = strip(lines[current_line])

        if startswith(line, "def ") || startswith(line, "class ")
            start_line = current_line
            name = Symbol(split(line)[2])
            is_function = startswith(line, "def ")

            # Find the end of the function or class
            end_line = find_block_end(lines, current_line)

            chunk = join(lines[start_line:end_line], '\n')
            signature_hash = hash(chunk)

            def = PythonSourceChunk(
                name=name,
                signature_hash=signature_hash,
                start_line_code=start_line,
                end_line_code=end_line,
                file_path=file_path,
                is_function=is_function,
                chunk=chunk,
                import_path=import_path
            )
            push!(source_defs, def)

            current_line = end_line + 1
        else
            current_line += 1
        end
    end

    return source_defs
end

function find_block_end(lines, start_line)
    indent_level = count_leading_spaces(lines[start_line])
    for i in (start_line + 1):length(lines)
        if !isempty(strip(lines[i])) && count_leading_spaces(lines[i]) <= indent_level
            return i - 1
        end
    end
    return length(lines)
end

function count_leading_spaces(line)
    return length(line) - length(lstrip(line))
end


