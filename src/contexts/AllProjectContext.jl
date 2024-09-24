using PromptingTools.Experimental.RAGTools

@kwdef mutable struct AllProjectContext <: AbstractContextProcessor
    context_node::ContextNode = ContextNode(tag="AllProject", element="File")
    call_counter::Int = 0
    past_questions::Vector{String} = String[]
    max_past_questions::Int = 4
    chunker::FullFileChunker = FullFileChunker()
end

function get_context(processor::AllProjectContext, question::String, ai_state, shell_results=nothing)
    processor.call_counter += 1
    push!(processor.past_questions, question)
    if length(processor.past_questions) > processor.max_past_questions
        popfirst!(processor.past_questions)
    end

    conv = curr_conv(ai_state)
    all_files = get_project_files(conv.rel_project_paths)
    
    chunks, sources = RAGTools.get_chunks(processor.chunker, all_files)
    
    add_or_update_source!(processor.context_node, sources, chunks)
    
    return processor.context_node
end

