using AISH: get_project_files, format_file_content
using PromptingTools.Experimental.RAGTools
import AISH

@kwdef mutable struct CodebaseContext <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
end

@kwdef mutable struct CodebaseContextV2 <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
    past_questions::Vector{String} = String[]
    max_past_questions::Int = 4
end

function get_context(processor::CodebaseContext, question::String, ai_state, shell_results)
    processor.call_counter += 1
    conv = curr_conv(ai_state)
    all_files = get_project_files(conv.rel_project_paths)
    selected_files, _ = get_relevant_files(question, all_files; suppress_output=true)
    
    new_files, updated_files, unchanged_files, new_contents, updated_contents = process_selected_files(processor, selected_files)
    
    print_context_updates(new_files, updated_files, unchanged_files)

    new_files_content = isempty(new_files) ? "" : """
    ## Files:
    $(join(new_contents, "\n\n"))
    """
    
    updated_files_content = isempty(updated_files) ? "" : """
    ## Files with newer version:
    $(join(updated_contents, "\n\n"))
    """

    return new_files_content * "\n" * updated_files_content
end

function get_context(processor::CodebaseContextV2, question::String, ai_state, shell_results)
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
    selected_files, _ = get_relevant_files(combined_questions, all_files; suppress_output=true)
    
    new_files, updated_files, unchanged_files, new_contents, updated_contents = process_selected_files(processor, selected_files)
    
    print_context_updates(new_files, updated_files, unchanged_files)

    new_files_content = isempty(new_files) ? "" : """
    ## Files:
    $(join(new_contents, "\n\n"))
    """
    
    updated_files_content = isempty(updated_files) ? "" : """
    ## Files with newer version:
    $(join(updated_contents, "\n\n"))
    """

    return new_files_content * "\n" * updated_files_content
end

function AISH.cut_history!(processor::CodebaseContext, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
end

function AISH.cut_history!(processor::CodebaseContextV2, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
    # We don't need to cut past_questions here as it's already limited by max_past_questions
end

