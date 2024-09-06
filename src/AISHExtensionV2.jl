using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, save_user_message
import AISH

@kwdef mutable struct EasyContextCreatorV2 <: AbstractContextCreator
    keep::Int=14
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    tracked_sources::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    message_counter::Int = 0
end

function AISH.get_cache_setting(::EasyContextCreatorV2)
    return :all
end

get_context_for_question_V2(creator::EasyContextCreatorV2, question) = begin
    result = get_context(question; suppress_output=true)
    new_sources = String[]
    unchanged_sources = String[]
    context = String[]
    
    for (i, source) in enumerate(result.sources)
        if !haskey(creator.tracked_sources, source)
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            creator.tracked_sources[source] = (creator.message_counter, result.context[i])
        elseif creator.tracked_sources[source][2] != result.context[i]
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            creator.tracked_sources[source] = (creator.message_counter, result.context[i])
        else
            push!(unchanged_sources, source)
        end
    end
    
    # Print the number of context sources in green
    printstyled("Number of context sources: ", color=:green, bold=true)
    printstyled(length(result.sources), "\n", color=:green)
    
    # Print the context sources in a styled manner
    for source in new_sources
        printstyled("  [NEW] $source\n", color=:blue)
    end
    for source in unchanged_sources
        printstyled("  [UNCHANGED] $source\n", color=:light_black)
    end
    
    join(context, "\n")
end

function get_all_relevant_project_files(creator::EasyContextCreatorV2, path, question)
    all_files = get_project_files(path)
    selected_files, fileindex = get_relevant_files(question, all_files; suppress_output=true)
    
    new_files = String[]
    updated_files = String[]
    unchanged_files = String[]
    new_contents = String[]
    updated_contents = String[]
    
    for file in selected_files
        formatted_content = format_file_content(file)
        
        if !haskey(creator.tracked_files, file)
            push!(new_files, file)
            push!(new_contents, formatted_content)
            creator.tracked_files[file] = (creator.message_counter, formatted_content)
        elseif creator.tracked_files[file][2] != formatted_content
            push!(updated_files, file)
            push!(updated_contents, formatted_content)
            creator.tracked_files[file] = (creator.message_counter, formatted_content)
        else
            push!(unchanged_files, file)
        end
    end
    
    return (new_files, new_contents, updated_files, updated_contents), (new_files, updated_files, unchanged_files)
end

function cut_old_files_n_msgs!(conv, creator::EasyContextCreatorV2)
    cut_history!(conv, keep=creator.keep)
    oldest_kept_message = max(1, creator.message_counter - 2 * creator.keep + 1)
    for (filepath, (message_num, _)) in creator.tracked_files
        if message_num < oldest_kept_message
            delete!(creator.tracked_files, filepath)
        end
    end
    for (source, (message_num, _)) in creator.tracked_sources
        if message_num < oldest_kept_message
            delete!(creator.tracked_sources, source)
        end
    end
end

function increment_message_counter!(creator::EasyContextCreatorV2)
    creator.message_counter += 2  # Increment by 2 to account for user message and AI response
end

AISH.prepare_user_message!(ctx::EasyContextCreatorV2, ai_state, question, shell_results) = begin
    conv = curr_conv(ai_state)
    
    # Increment message counter
    increment_message_counter!(ctx)
    
    # Create tasks for asynchronous execution
    codebase_task = @async get_all_relevant_project_files(ctx, conv.rel_project_paths, question)
    context_task = @async get_context_for_question_V2(ctx, question)
    
    # Wait for both tasks to complete
    (new_files, new_contents, updated_files, updated_contents), (new_files, updated_files, unchanged_files) = fetch(codebase_task)
    context_msg = fetch(context_task)
    
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
    
    # Clean old files and cut history
    cut_old_files_n_msgs!(conv, ctx)
    
    codebase_ctx = """
    The codebase you are working on will be in user messages. 
    Before the files there will be "## Files:" and "## Files with newer version:" sections.

    If a code has been updated or got some change they will be mentioned in the Files with newer version section, and always this will represent the newest version of their file content. If something is not like you proposed and is not mentioned in the "Files with newer version" is probably because the change was partially accepted or not accepted, we might need to rethink our idea.
    """
    # Create system message (without file contents)
    if conv.system_message.content != SYSTEM_PROMPT(;ctx=codebase_ctx)
        conv.system_message = Message(timestamp=now(), role=:system, content=SYSTEM_PROMPT(;ctx=codebase_ctx))
        @info "System message updated!"
    end
    formatted_results = format_shell_results(shell_results)

    # Prepare the content for the user message
    new_files_content = isempty(new_files) ? "" : """
    ## Files:
    $(join(new_contents, "\n\n"))
    """
    
    updated_files_content = isempty(updated_files) ? "" : """
    ## Files with newer version:
    $(join(updated_contents, "\n\n"))
    """
    context_msg = isempty(context_msg) ? "" : """
    Possible useful functions:
    $context_msg
    """
    question = """
    ## User question:
    $(question)
    """

    new_msg = """
    $(formatted_results)
    $(new_files_content)
    $(updated_files_content)
    $(context_msg)
    $(question)
    """
    new_msg
end

