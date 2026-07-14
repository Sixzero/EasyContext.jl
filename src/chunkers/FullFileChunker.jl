import PromptingTools: recursive_splitter
using RAGTools
using RAGTools: AbstractChunker

export FullFileChunker

abstract type AbstractChunkerWrappers <: AbstractChunker end

struct FullFileChunker <: AbstractChunkerWrappers
    chunker::NewlineChunker{FileChunk}
end
# Either pass an explicit inner `chunker`, or forward keywords (max_tokens, estimation_method, ...) to a new NewlineChunker.
function FullFileChunker(; chunker=nothing, kwargs...)
    isnothing(chunker) && return FullFileChunker(NewlineChunker{FileChunk}(; kwargs...))
    isempty(kwargs) || throw(ArgumentError("FullFileChunker: pass either `chunker` or NewlineChunker keywords, not both"))
    FullFileChunker(chunker)
end
# TODO later on support overlap chunks.
# @kwdef struct OverlapFileChunker <: AbstractChunkerWrappers 
#     chunker::NewlineChunker{OverlapFileChunk} = NewlineChunker{OverlapFileChunk}()
# end

# Delegate to the inner NewlineChunker, loading file contents from the given paths.
function RAGTools.get_chunks(chunker::AbstractChunkerWrappers, file_paths::Vector{<:AbstractString}; root_path::AbstractString = "", verbose::Bool = true)
    paths = [Path(p) for p in file_paths]
    get_chunks_w_root_path(chunker.chunker, paths; root_path, verbose)
end

# function RAGTools.load_text(chunker::Type{FileChunk}; content::AbstractString, source::AbstractString)
#     @assert isfile(source) "Path $source does not exist"
#     @assert content !== source
#     @show content
#     return content, source
# end
function RAGTools.load_text(chunker::Type{FileChunk}, source::AbstractPath, root_path)
    filepath = joinpath(root_path, string(source))
    @assert isfile(filepath) "Path $source does not exist"
    return read(filepath, String)
end
