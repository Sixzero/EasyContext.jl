using FilePathsBase
using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractChunker
const RAG = RAGTools

export NewlineChunker

@kwdef struct NewlineChunker{T<:AbstractChunk} <: AbstractChunker 
    max_tokens::Int = 8000
    overlap_tokens::Int = 200
    estimation_method::TokenEstimationMethod = CharCountDivTwo
    line_number_token_estimate::Int = 10
end

function RAG.get_chunks(chunker::NewlineChunker{T},
    file_paths::Vector{<:AbstractPath};
    sources=nothing,
    verbose::Bool = true) where T
    files_or_docs = [RAG.load_text(T, f)[1] for f in file_paths]
    if isnothing(files_or_docs)
        return Vector{T}()
    end
    return RAG.get_chunks(chunker, files_or_docs; sources=file_paths, verbose)
end

function RAG.get_chunks(chunker::NewlineChunker{T},
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{<:AbstractPath},
    verbose::Bool = true) where T

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{T}()

    formatter_tokens = estimate_tokens(string(T(; source=SourcePath(; path=""))), chunker.estimation_method)

    for i in eachindex(files_or_docs)
        doc_raw, source = files_or_docs[i], "$(sources[i])"
        if isempty(doc_raw)
            push!(output_chunks, T(; source=SourcePath(; path=source), content=""))
            continue
        end

        effective_max_tokens = chunker.max_tokens - formatter_tokens - chunker.line_number_token_estimate

        if estimate_tokens(doc_raw, chunker.estimation_method) <= effective_max_tokens
            push!(output_chunks, T(; source=SourcePath(; path=source), content=doc_raw))
        else
            chunks, line_ranges = split_text_into_chunks(doc_raw, chunker.estimation_method, effective_max_tokens)

            for (chunk_index, (chunk, (start_line, end_line))) in enumerate(zip(chunks, line_ranges))
                chunk_tokens = estimate_tokens(chunk, chunker.estimation_method)
                if chunk_tokens > effective_max_tokens * 1.2
                    @warn "Chunk $(source):$(start_line)-$(end_line) exceeds token limit ($(chunk_tokens) > $(effective_max_tokens)). Skipping."
                    continue
                end
                push!(output_chunks, T(; content=chunk, source=SourcePath(; path=source, from_line=start_line, to_line=end_line)))
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