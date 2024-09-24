using PromptingTools.Experimental.RAGTools

@kwdef mutable struct CodebaseContext <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
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

function cut_history!(processor::CodebaseContext, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
end
