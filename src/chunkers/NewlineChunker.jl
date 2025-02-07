using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractChunker
const RAG = RAGTools

export NewlineChunker

@kwdef struct NewlineChunker{T<:AbstractChunk} <: AbstractChunker 
    max_tokens::Int = 8000
    overlap_tokens::Int = 200
    estimation_method::TokenEstimationMethod = CharCountDivTwo
    formatter::Function = get_chunk_standard_format
    line_number_token_estimate::Int = 10
end

function RAG.get_chunks(chunker::NewlineChunker{T},
    files_or_docs::Vector{<:AbstractString};
    sources::AbstractVector{<:AbstractString} = files_or_docs,
    verbose::Bool = true) where T

    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{T}()

    formatter_tokens = estimate_tokens(chunker.formatter("", ""), chunker.estimation_method)

    for i in eachindex(files_or_docs, sources)
        doc_raw, source = RAG.load_text(T, files_or_docs[i]; source = sources[i])
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
                push!(output_chunks, T(; source=SourcePath(; path=source, from_line=start_line, to_line=end_line), content=chunk))
            end
        end
    end
    return output_chunks
end
