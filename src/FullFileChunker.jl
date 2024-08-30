using PromptingTools: recursive_splitter
using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

struct FullFileChunker <: AbstractChunker 
  separators::Vector{String}
  max_length::Int
end
FullFileChunker(; separators=["\n\n", ". ", "\n", " "], max_length=10000) = FullFileChunker(separators, max_length)

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

    # Calculate line numbers for each chunk
    line_numbers = calculate_line_numbers(chunks, doc_raw, )

    append!(output_chunks, chunks)
    append!(output_sources, ["$(source):$(start_line)-$(end_line)" for (start_line, end_line) in line_numbers])
  end
  return output_chunks, output_sources
end
function RAG.load_text(chunker::FullFileChunker, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path $input does not exist"
    return read(input, String), source
end
# just a rough estimation, we hope chunks are one after the other, otherwise we would need to check their position in the doc_raw..
function calculate_line_numbers(chunks::Vector{String}, doc_raw, )
  line_numbers = Vector{Tuple{Int, Int}}()
  start_line = 1
  
  for chunk in chunks
      chunk_lines = split(chunk, '\n')
      end_line = start_line + length(chunk_lines) - 1
      push!(line_numbers, (start_line, end_line))
      length(chunk_lines)>0 && (start_line = end_line + 1)
  end
  
  return line_numbers
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
