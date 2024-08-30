import PromptingTools.Experimental.RAGTools: get_chunks, AbstractEmbedder
import PromptingTools.Experimental.RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import PromptingTools.Experimental.RAGTools: ChunkIndex, AbstractChunker

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
end

struct PythonSourceChunker <: AbstractChunker end

function get_chunks(chunker::PythonSourceChunker,
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{<:AbstractString} = files_or_docs,
    verbose::Bool = true)

    @assert (length(sources) == length(files_or_docs)) "Length of `sources` must match length of `files_or_docs`"

    output_chunks = Vector{SubString{String}}()
    output_sources = Vector{eltype(sources)}()

    for i in eachindex(files_or_docs, sources)
        defs = process_python_file(files_or_docs[i])
        chunks = ["$(def.file_path):$(def.start_line_code)\n" * def.chunk for def in defs]

        @assert all(!isempty, chunks) "Chunks must not be empty. The following are empty: $(findall(isempty, chunks))"
    
        sources = ["$(def.file_path):$(def.start_line_code)" for def in defs]
        append!(output_chunks, chunks)
        append!(output_sources, sources)
    end

    return output_chunks, output_sources
end

function process_python_file(file_path::AbstractString, verbose::Bool=true)
    verbose && @info "Processing Python file: $file_path"
    content = read(file_path, String)
    lines = split(content, '\n')
    defs = PythonSourceChunk[]
    
    current_function = nothing
    current_docstring = []
    in_docstring = false
    
    for (i, line) in enumerate(lines)
        stripped_line = strip(line)
        
        if startswith(stripped_line, "def ")
            if !isnothing(current_function)
                push!(defs, current_function)
            end
            
            func_name = match(r"def\s+(\w+)", stripped_line).captures[1]
            current_function = PythonSourceChunk(
                name = Symbol(func_name),
                signature_hash = hash(stripped_line),
                start_line_code = i,
                end_line_code = i,
                file_path = file_path,
                is_function = true
            )
            
            if !isempty(current_docstring)
                current_function.start_line_docs = current_docstring[1]
                current_function.end_line_docs = current_docstring[end]
            end
            
            in_docstring = false
            current_docstring = []
        elseif !isnothing(current_function)
            if stripped_line == "\"\"\"" || stripped_line == "'''"
                in_docstring = !in_docstring
                if in_docstring
                    current_docstring = [i]
                else
                    push!(current_docstring, i)
                end
            elseif !in_docstring && !isempty(stripped_line) && !startswith(stripped_line, " ")
                current_function.end_line_code = i - 1
                current_function.chunk = join(lines[current_function.start_line_docs:current_function.end_line_code], "\n")
                push!(defs, current_function)
                current_function = nothing
                current_docstring = []
            end
        end
    end
    
    if !isnothing(current_function)
        current_function.end_line_code = length(lines)
        current_function.chunk = join(lines[current_function.start_line_docs:current_function.end_line_code], "\n")
        push!(defs, current_function)
    end
    
    return defs
end

