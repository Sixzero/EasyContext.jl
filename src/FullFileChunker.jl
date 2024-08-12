using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

struct FullFileChunker <: AbstractChunker end

function RAG.get_chunks(chunker::FullFileChunker,
                    files_or_docs::Vector{<:AbstractString};
                    sources::AbstractVector{<:AbstractString} = files_or_docs,
                    verbose::Bool = true)
    
    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{String}()
    output_sources = Vector{eltype(sources)}()
    for i in eachindex(files_or_docs, sources)
        doc_raw, source = load_text(chunker, files_or_docs[i]; source = sources[i])
        isempty(doc_raw) && continue
        
        push!(output_chunks, doc_raw)
        push!(output_sources, source)
    end
    return output_chunks, output_sources
end
function RAG.load_text(chunker::FullFileChunker, input::AbstractString;[4,0.45]
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path $input does not exist"
    return read(input, String), source
end