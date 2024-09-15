using AISH: get_project_files, format_file_content
using PromptingTools.Experimental.RAGTools
import AISH

@kwdef mutable struct CodebaseContextV3 <: AbstractContextProcessor
    chunker::RAG.AbstractChunker = FullFileChunker()
    project_paths::Vector{String} = String[]
end

function (context::CodebaseContextV3)(input::Union{String, RAGContext})
    question = input isa RAGContext ? input.question : input
    chunks, sources = get_chunked_files(context)
    
    return RAGContext(SourceChunk(sources, chunks), question)
end

function get_chunked_files(context::CodebaseContextV3)
    all_files = get_project_files(context.project_paths)
    chunks, sources = RAGTools.get_chunks(context.chunker, all_files)
    return chunks, sources
end

function get_context(context::CodebaseContextV3, question::String, ai_state=nothing, shell_results=nothing)
    return context(question)
end

function AISH.cut_history!(context::CodebaseContextV3, keep::Int)
    # No history to cut in this context
end
