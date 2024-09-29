using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

@kwdef struct FullFileChunker <: AbstractChunker 
    separators::Vector{String}=["\n"]
    max_length::Int=10000
    overlap_lines::Int=10
end

# function FullFileChunker(; 
#     separators=["\n"], 
#     max_length=10000, 
#     overlap_lines=10
# )
#     FullFileChunker(separators, max_length, overlap_lines)
# end

function RAG.get_chunks(chunker::FullFileChunker,
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{<:AbstractString} = files_or_docs,
    verbose::Bool = true)

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{String}()
    output_sources = Vector{String}()

    for i in eachindex(files_or_docs, sources)
        doc_raw, source = RAG.load_text(chunker, files_or_docs[i]; source = sources[i])
        isempty(doc_raw) && (@warn("Missing content $(files_or_docs[i])"); continue)

        chunks = recursive_splitter(doc_raw, chunker.separators; max_length=chunker.max_length)

        
        if length(chunks) == 1
            push!(output_chunks, get_chunk_standard_format(source, chunks[1]))
            push!(output_sources, source)
        else
            chunks_with_overlap = chunks # apply_overlap(chunks, chunker.overlap_lines)
            line_numbers = calculate_line_numbers(chunks_with_overlap, doc_raw)
            
            for (chunk, (start_line, end_line)) in zip(chunks_with_overlap, line_numbers)
                chunk_source = "$(source):$(start_line)-$(end_line)"
                chunk_with_source = get_chunk_standard_format(chunk_source, chunk)
                push!(output_sources, chunk_source)
                push!(output_chunks, chunk_with_source)
            end
        end
    end
    return output_chunks, output_sources
end

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

function calculate_line_numbers(chunks::Vector{String}, doc_raw::String)
    line_numbers = Vector{Tuple{Int, Int}}()
    total_lines = count('\n', doc_raw) + 1
    current_line = 1
    
    for chunk in chunks
        chunk_lines = count('\n', chunk) + 1
        end_line = min(current_line + chunk_lines - 1, total_lines)
        push!(line_numbers, (current_line, end_line))
        current_line = end_line + 1
    end
    
    return line_numbers
end

function RAG.load_text(chunker::FullFileChunker, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path $input does not exist"
    return read(input, String), source
end

function reproduce_chunk(chunker::FullFileChunker, source::AbstractString)
    file_path, line_range = split(source, ':')
    start_line, end_line = parse.(Int, split(line_range, '-'))
    
    doc_raw = read(file_path, String)
    lines = split(doc_raw, '\n')
    chunk = join(lines[start_line:end_line], '\n')
    
    return chunk
end

struct NoSimilarityCheck <: RAG.AbstractSimilarityFinder end

function RAG.find_closest(
    finder::NoSimilarityCheck, 
    emb::AbstractMatrix{<:Real},
    query_emb::AbstractVector{<:Real}, 
    query_tokens::AbstractVector{<:AbstractString} = String[];
    kwargs...)

    # Get the number of chunks (columns in the embedding matrix)
    num_chunks = size(emb, 2)

    # Create a vector of all positions (1 to num_chunks)
    positions = collect(1:num_chunks)

    # Create a vector of scores (all set to 1.0 as we're not actually computing similarity)
    scores = ones(Float32, num_chunks)

    return positions, scores
end
