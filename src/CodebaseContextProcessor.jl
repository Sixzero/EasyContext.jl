using AISH: get_project_files, format_file_content
using PromptingTools.Experimental.RAGTools
import AISH

abstract type AbstractContextProcessor end

@kwdef mutable struct CodebaseContextProcessor <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
end

@kwdef mutable struct CodebaseContextProcessorV2 <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
    past_questions::Vector{String} = String[]
    max_past_questions::Int = 4
end

function get_context(processor::CodebaseContextProcessor, question::String, ai_state, shell_results)
    processor.call_counter += 1
    conv = curr_conv(ai_state)
    all_files = get_project_files(conv.rel_project_paths)
    selected_files, _ = get_relevant_files(question, all_files; suppress_output=true)
    
    new_files = String[]
    updated_files = String[]
    unchanged_files = String[]
    new_contents = String[]
    updated_contents = String[]
    
    # First, check all tracked files for updates
    for (file, (_, old_content)) in processor.tracked_files
        current_content = format_file_content(file)
        if old_content != current_content
            push!(updated_files, file)
            push!(updated_contents, current_content)
            processor.tracked_files[file] = (processor.call_counter, current_content)
        end
    end
    
    # Then, process selected files
    for file in selected_files
        if !haskey(processor.tracked_files, file)
            formatted_content = format_file_content(file)
            push!(new_files, file)
            push!(new_contents, formatted_content)
            processor.tracked_files[file] = (processor.call_counter, formatted_content)
        elseif file ∉ updated_files
            push!(unchanged_files, file)
        end
    end
    
    # Print file information
    printstyled("Number of files selected: ", color=:green, bold=true)
    printstyled(length(new_files) + length(updated_files) + length(unchanged_files), "\n", color=:green)
    
    for file in new_files
        printstyled("  [NEW] $file\n", color=:blue)
    end
    for file in updated_files
        printstyled("  [UPDATED] $file\n", color=:yellow)
    end
    for file in unchanged_files
        printstyled("  [UNCHANGED] $file\n", color=:light_black)
    end

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

function get_context(processor::CodebaseContextProcessorV2, question::String, ai_state, shell_results)
    processor.call_counter += 1
    push!(processor.past_questions, question)
    if length(processor.past_questions) > processor.max_past_questions
        popfirst!(processor.past_questions)
    end

    conv = curr_conv(ai_state)
    all_files = get_project_files(conv.rel_project_paths)
    selected_files, _ = get_relevant_files(question, all_files; suppress_output=true)
    
    new_files = String[]
    updated_files = String[]
    unchanged_files = String[]
    new_contents = String[]
    updated_contents = String[]
    
    # First, check all tracked files for updates
    for (file, (_, old_content)) in processor.tracked_files
        current_content = format_file_content(file)
        if old_content != current_content
            push!(updated_files, file)
            push!(updated_contents, current_content)
            processor.tracked_files[file] = (processor.call_counter, current_content)
        end
    end
    
    # Then, process selected files
    for file in selected_files
        if !haskey(processor.tracked_files, file)
            formatted_content = format_file_content(file)
            push!(new_files, file)
            push!(new_contents, formatted_content)
            processor.tracked_files[file] = (processor.call_counter, formatted_content)
        elseif file ∉ updated_files
            push!(unchanged_files, file)
        end
    end
    
    # Print file information
    printstyled("Number of files selected: ", color=:green, bold=true)
    printstyled(length(new_files) + length(updated_files) + length(unchanged_files), "\n", color=:green)
    
    for file in new_files
        printstyled("  [NEW] $file\n", color=:blue)
    end
    for file in updated_files
        printstyled("  [UPDATED] $file\n", color=:yellow)
    end
    for file in unchanged_files
        printstyled("  [UNCHANGED] $file\n", color=:light_black)
    end

    new_files_content = isempty(new_files) ? "" : """
    ## Files:
    $(join(new_contents, "\n\n"))
    """
    
    updated_files_content = isempty(updated_files) ? "" : """
    ## Files with newer version:
    $(join(updated_contents, "\n\n"))
    """

    past_questions_content = isempty(processor.past_questions) ? "" : """
    ## Past questions:
    $(join(processor.past_questions, "\n"))
    """

    return past_questions_content * "\n" * new_files_content * "\n" * updated_files_content
end

function AISH.cut_history!(processor::CodebaseContextProcessor, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
end

function AISH.cut_history!(processor::CodebaseContextProcessorV2, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
    # We don't need to cut past_questions here as it's already limited by max_past_questions
end

