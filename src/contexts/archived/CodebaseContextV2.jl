using PromptingTools.Experimental.RAGTools

@kwdef mutable struct CodebaseContextV2 <: AbstractContextProcessor
    context_node::ContextNode = ContextNode(tag="Codebase", element="File")
    call_counter::Int = 0
    past_questions::Vector{String} = String[]
    max_past_questions::Int = 4
end


function get_context(processor::CodebaseContextV2, question::String, ai_state, shell_results=nothing)
    processor.call_counter += 1
    push!(processor.past_questions, question)
    if length(processor.past_questions) > processor.max_past_questions
        popfirst!(processor.past_questions)
    end

    # Create a combined question string with past questions
    combined_questions = join(["$(i). $(q)" for (i, q) in enumerate(processor.past_questions)], "\n")
    combined_questions *= "\n$(length(processor.past_questions) + 1). [LATEST] $question"

    conv = curr_conv(ai_state)
    all_files = get_project_files(conv.rel_project_paths)
    contents, sources, _ = get_relevant_files(combined_questions, all_files; suppress_output=true)
    
    add_or_update_source!(processor.context_node, sources, contents)
    
    return processor.context_node
end


function cut_history!(processor::CodebaseContextV2, keep::Int)
    cut_history!(processor.context_node, keep)
    # We don't need to cut past_questions here as it's already limited by max_past_questions
end

