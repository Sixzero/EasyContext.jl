using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractChunker
const RAG = RAGTools

export FullFileChunker

@kwdef struct FullFileChunker <: AbstractChunker 
    max_tokens::Int = 8000
    overlap_tokens::Int = 200
    estimation_method::TokenEstimationMethod = CharCountDivTwo
    formatter::Function = get_chunk_standard_format
    line_number_token_estimate::Int = 10 # just an estimation on how much linenumbers in the source will matter.
end

function RAG.get_chunks(chunker::FullFileChunker,
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{<:AbstractString} = files_or_docs,
    verbose::Bool = true)

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{FileChunk}()

    formatter_tokens = estimate_tokens(chunker.formatter("", ""), chunker.estimation_method)

    for i in eachindex(files_or_docs, sources)
        doc_raw, source = RAG.load_text(chunker, files_or_docs[i]; source = sources[i])
        if isempty(doc_raw)
            push!(output_chunks, FileChunk(; source=SourcePath(; path=source), content=""))  # Return empty string for empty files
            continue
        end

        # Calculate the effective max tokens by subtracting formatter and line range number tokens
        effective_max_tokens = chunker.max_tokens - formatter_tokens - chunker.line_number_token_estimate

        if estimate_tokens(doc_raw, chunker.estimation_method) <= effective_max_tokens
            # If the entire file fits within the token limit, don't split it
            push!(output_chunks, FileChunk(; source=SourcePath(; path=source), content=doc_raw))
        else
            chunks, line_ranges = split_text_into_chunks(doc_raw, chunker.estimation_method, effective_max_tokens)

            for (chunk_index, (chunk, (start_line, end_line))) in enumerate(zip(chunks, line_ranges))
                chunk_tokens = estimate_tokens(chunk, chunker.estimation_method)
                if chunk_tokens > effective_max_tokens
                    @warn "Chunk $(source):$(start_line)-$(end_line) exceeds token limit ($(chunk_tokens) > $(effective_max_tokens)). Skipping."
                    continue
                end
                push!(output_chunks, FileChunk(; source=SourcePath(; path=source, from_line=start_line, to_line=end_line), content=chunk))
            end
        end
    end
    return output_chunks
end

function split_text_into_chunks(text::String, estimation_method::TokenEstimationMethod, max_tokens::Int)
    chunks = String[]
    line_ranges = Tuple{Int,Int}[]
    current_chunk = String[]
    current_tokens = 0
    lines = split(text, '\n')
    start_line = 1

    for (line_number, line) in enumerate(lines)
        line_tokens = estimate_tokens(line, estimation_method)
        
        if current_tokens + line_tokens > max_tokens && !isempty(current_chunk)
            push!(chunks, join(current_chunk, '\n'))
            push!(line_ranges, (start_line, line_number - 1))
            current_chunk = String[]
            current_tokens = 0
            start_line = line_number
        end
        
        push!(current_chunk, line)
        current_tokens += line_tokens
    end

    if !isempty(current_chunk)
        push!(chunks, join(current_chunk, '\n'))
        push!(line_ranges, (start_line, length(lines)))
    end

    return chunks, line_ranges
end

function RAG.load_text(chunker::FullFileChunker, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path $input does not exist"
    return read(input, String), source
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
    
    return chunker.formatter(source, content)
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
