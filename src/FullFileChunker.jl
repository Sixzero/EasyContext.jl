using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

struct FullFileChunker <: AbstractChunker 
    separators::Vector{String}
    max_length::Int
    overlap_lines::Int
end

function FullFileChunker(; 
    separators=["\n\n", ". ", "\n", " "], 
    max_length=10000, 
    overlap_lines=10
)
    FullFileChunker(separators, max_length, overlap_lines)
end

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

        # Split the content using recursive_splitter
        chunks = recursive_splitter(doc_raw, chunker.separators; max_length=chunker.max_length)
        
        # Apply overlap if the file was split
        if length(chunks) > 1
            original_line_numbers = calculate_line_numbers(chunks, doc_raw)
            chunks = apply_overlap(chunks, chunker.overlap_lines)
            adjusted_line_numbers = adjust_line_numbers(original_line_numbers, chunker.overlap_lines, count('\n', doc_raw) + 1)
            append!(output_sources, ["$(source):$(start_line)-$(end_line)" for (start_line, end_line) in adjusted_line_numbers])
        else
            append!(output_sources, [source for _ in chunks])
        end

        chunks_with_sources = ["# $(source)\n$(chunk)" for chunk in chunks]
        append!(output_chunks, chunks_with_sources)
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
            chunk = join(vcat(chunk_lines, next_chunk_lines[1:overlap_end]), '\n')
        end
        
        push!(overlapped_chunks, chunk)
    end
    return overlapped_chunks
end

function RAG.load_text(chunker::FullFileChunker, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path $input does not exist"
    return read(input, String), source
end

function calculate_line_numbers(chunks::Vector{String}, doc_raw)
    line_numbers = Vector{Tuple{Int, Int}}()
    start_line = 1
    
    for chunk in chunks
        chunk_lines = split(chunk, '\n')
        end_line = start_line + length(chunk_lines) - 1
        push!(line_numbers, (start_line, end_line))
        length(chunk_lines) > 0 && (start_line = end_line + 1)
    end
    
    return line_numbers
end

function adjust_line_numbers(original_line_numbers::Vector{Tuple{Int, Int}}, overlap_lines::Int, total_lines::Int)
    adjusted_line_numbers = Vector{Tuple{Int, Int}}()
    
    for (i, (start_line, end_line)) in enumerate(original_line_numbers)
        adjusted_start = max(1, start_line - (i > 1 ? overlap_lines : 0))
        adjusted_end = min(total_lines, end_line + (i < length(original_line_numbers) ? overlap_lines : 0))
        push!(adjusted_line_numbers, (adjusted_start, adjusted_end))
    end
    
    return adjusted_line_numbers
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
