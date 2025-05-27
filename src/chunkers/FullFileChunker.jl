using PromptingTools: recursive_splitter
using RAGTools
using RAGTools: AbstractChunker

export FullFileChunker

abstract type AbstractChunkerWrappers <: AbstractChunker end

@kwdef struct FullFileChunker <: AbstractChunkerWrappers 
    chunker::NewlineChunker{FileChunk} = NewlineChunker{FileChunk}()
end
# TODO later on support overlap chunks.
# @kwdef struct OverlapFileChunker <: AbstractChunkerWrappers 
#     chunker::NewlineChunker{OverlapFileChunk} = NewlineChunker{OverlapFileChunk}()
# end

# Delegate methods to the internal GeneralChunker
RAGTools.get_chunks(chunker::AbstractChunkerWrappers, docs::Vector{<:AbstractString}; sources::AbstractVector{<:AbstractString} = docs, kwargs...) = RAGTools.get_chunks(chunker.chunker, docs; sources, kwargs...)

# function RAGTools.load_text(chunker::Type{FileChunk}; content::AbstractString, source::AbstractString)
#     @assert isfile(source) "Path $source does not exist"
#     @assert content !== source
#     @show content
#     return content, source
# end
function RAGTools.load_text(chunker::Type{FileChunk}, source::AbstractPath)
    @assert isfile(source) "Path $source does not exist"
    return read(source, String), source
end

function reproduce_chunk(chunker::FullFileChunker, source::AbstractString)
    if ':' in source
        file_path, line_range = split(source, ':')
        start_line, end_line = parse.(Int, split(line_range, '-'))

        lines = readlines(file_path)
        content = join(lines[start_line:end_line], "\n")
    else
        content = read(source, String)
    end
    
    return chunker.chunker.formatter(source, content)
end

# these last part of the file is not really useful.
function apply_overlap(chunks::Vector{String}, overlap_lines::Int)
    overlapped_chunks = String[]
    for i in 1:length(chunks)
        chunk = chunks[i]
        chunk_lines = split(chunk, '\n')
        
        if i > 1
            # Add overlap from previous chunk
            prev_chunk_lines = split(chunks[i-1], '\n')
            overlap_start = max(1, length(prev_chunk_lines) - overlap_lines + 1)
            chunk = join(vcat(prev_chunk_lines[overlap_start:end], chunk_lines), '\n')
        end
        
        if i < length(chunks)
            # Add overlap to next chunk
            next_chunk_lines = split(chunks[i+1], '\n')
            overlap_end = min(length(chunk_lines), overlap_lines)
            chunk = join(vcat(chunk_lines, next_chunk_lines[1:min(overlap_end, end)]), '\n')
        end
        
        push!(overlapped_chunks, chunk)
    end
    return overlapped_chunks
end