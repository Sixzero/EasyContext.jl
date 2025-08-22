using FilePathsBase
using PromptingTools: recursive_splitter
using RAGTools
using RAGTools: AbstractChunker
using PyCall
using LLMRateLimiters: EncodingStatePBE, partial_encode!, GreedyBPETokenizer, load_bpe_tokenizer


export NewlineChunker

@kwdef struct NewlineChunker{T<:AbstractChunk} <: AbstractChunker 
    max_tokens::Int = 8000
    overlap_tokens::Int = 200
    estimation_method::TokenEstimationMethod = CharCountDivTwo
    line_number_token_estimate::Int = 10
end

function RAGTools.get_chunks(chunker::NewlineChunker{T},
    file_paths::Vector{<:AbstractPath};
    sources=nothing,
    verbose::Bool = true) where T
    files_or_docs = [RAGTools.load_text(T, f)[1] for f in file_paths]
    if isnothing(files_or_docs)
        return Vector{T}()
    end
    return RAGTools.get_chunks(chunker, files_or_docs; sources=file_paths, verbose)
end

function RAGTools.get_chunks(chunker::NewlineChunker{ChunkType},
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{S},
    verbose::Bool = true) where {ChunkType, S<:Union{AbstractPath,AbstractString}}

    SAFETY_MAX_TOKEN_PERCENTAGE = 0.9 # depends on how accurate the approximator token counter is. its max difference is around 6-7%
    ACCURATE_THRESHOLD_RATIO = 0.5

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{ChunkType}()

    formatter_tokens = estimate_tokens(string(ChunkType(; source="", content="")), chunker.estimation_method)
    effective_max_tokens = chunker.max_tokens * SAFETY_MAX_TOKEN_PERCENTAGE - formatter_tokens - chunker.line_number_token_estimate

    for i in eachindex(files_or_docs)
        doc_raw, source = files_or_docs[i], "$(sources[i])"
        if isempty(doc_raw)
            push!(output_chunks, ChunkType(; source=source, content=""))
            continue
        end

        estimated_tokens = estimate_tokens(doc_raw, chunker.estimation_method)
        if estimated_tokens <= effective_max_tokens * ACCURATE_THRESHOLD_RATIO
            push!(output_chunks, ChunkType(; source=source, content=doc_raw))
        else
            chunks, line_ranges = split_text_into_chunks_accurately(doc_raw, effective_max_tokens)
            is_cut = length(chunks) > 1
            
            for (chunk_index, (chunk, (start_line, end_line))) in enumerate(zip(chunks, line_ranges))
                chunk_obj = is_cut ? ChunkType(; source, content=chunk, from_line=start_line, to_line=end_line) : ChunkType(; source, content=chunk)
                push!(output_chunks, chunk_obj)
            end
        end
    end
    return output_chunks
end

function split_text_into_chunks(text::String, estimation_method::TokenEstimationMethod, max_tokens::Number)
    chunks = String[]
    line_ranges = Tuple{Int,Int}[]
    current_tokens = 0
    lines = split(text, '\n')
    start_line = 1

    for (line_number, line) in enumerate(lines)
        line_tokens = estimate_tokens(line, estimation_method)
        
        if current_tokens + line_tokens > max_tokens && line_number > start_line
            push!(chunks, join(view(lines, start_line:line_number-1), '\n'))
            push!(line_ranges, (start_line, line_number - 1))
            current_tokens = 0
            start_line = line_number
        end
        
        current_tokens += line_tokens
    end

    if start_line <= length(lines)
        push!(chunks, join(view(lines, start_line:length(lines)), '\n'))
        push!(line_ranges, (start_line, length(lines)))
    end

    return chunks, line_ranges
end

function split_text_into_chunks_accurately(text::AbstractString, max_tokens::Number, verbose = true, separator::String = "\n")
    chunks = String[]
    line_ranges = Tuple{Int,Int}[]
    lines = split(text, separator)
    start_line = 1
    
    tokenizer = load_bpe_tokenizer("cl100k_base", verbose)
    state = EncodingStatePBE()
    
    for (line_number, line) in enumerate(lines)
        # Add this line to the current state
        line_with_sep = line * separator
        partial_encode!(tokenizer, line_with_sep, state)
        token_count = length(state.result)

        if token_count > max_tokens
            if line_number > start_line
                # Current chunk exceeds max tokens, finalize it
                chunk_text = join(view(lines, start_line:line_number-1), separator)
                push!(chunks, chunk_text)
                push!(line_ranges, (start_line, line_number - 1))
            end

            # Reset for next chunk
            state = EncodingStatePBE()
            partial_encode!(tokenizer, line_with_sep, state)
            
            # Check if single line is too long after reset
            if length(state.result) > max_tokens
                if separator == "\n"
                    # Split this line using sentence separator
                    sub_chunks, sub_ranges = split_text_into_chunks_accurately(line, max_tokens, verbose, ".")
                    append!(chunks, sub_chunks)
                    # Adjust line ranges for sub-chunks
                    for (sub_start, sub_end) in sub_ranges
                        push!(line_ranges, (line_number, line_number))
                    end
                    state = EncodingStatePBE()
                    start_line = line_number + 1
                    continue
                else
                    # Already at sentence level, just add as is (truncate if needed)
                    @warn "Sentences TOO LONG, we cannot handle! Length: $(length(line))"
                    push!(chunks, line)
                    push!(line_ranges, (line_number, line_number))
                    state = EncodingStatePBE()
                    start_line = line_number + 1
                    continue
                end
            end
            
            start_line = line_number
        end
    end
    
    # Add the final chunk if there are remaining lines
    if start_line <= length(lines)
        push!(chunks, join(view(lines, start_line:length(lines)), separator))
        push!(line_ranges, (start_line, length(lines)))
    end
    
    return chunks, line_ranges
end