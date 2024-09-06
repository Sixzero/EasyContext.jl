using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, save_user_message, format_shell_results
import AISH

# Context Processors
abstract type AbstractContextProcessor end

function get_context(p::AbstractContextProcessor, question::String, ai_state, shell_results)
    @warn "get_context not implemented for this processor: $p"
    return ""
end

function AISH.cut_history!(p::AbstractContextProcessor, keep::Int)
    @warn "cut_history! not implemented for this processor: $p"
end

@kwdef mutable struct CodebaseContextProcessor <: AbstractContextProcessor
    tracked_files::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
end

@kwdef mutable struct ShellContextProcessor <: AbstractContextProcessor
    call_counter::Int = 0
end

@kwdef mutable struct JuliaPackageContextProcessor <: AbstractContextProcessor
    tracked_sources::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
end

# Async Joiner
@kwdef mutable struct AsyncContextJoiner
    processors::Vector{AbstractContextProcessor}
    keep::Int = 10 # the max length history should be kept
end

@kwdef mutable struct EasyContextCreatorV3 <: AbstractContextCreator
    joiner::AsyncContextJoiner = AsyncContextJoiner(
        processors=[
            CodebaseContextProcessor(),
            ShellContextProcessor(),
            JuliaPackageContextProcessor(),
        ]
    )
end

function AISH.get_cache_setting(::EasyContextCreatorV3)
    return :all
end

# Implement context processors
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

function get_context(processor::ShellContextProcessor, question::String, ai_state, shell_results)
    processor.call_counter += 1
    return format_shell_results(shell_results)
end

function get_context(processor::JuliaPackageContextProcessor, question::String, ai_state, shell_results)
    processor.call_counter += 1
    result = get_context(question; suppress_output=true)
    new_sources = String[]
    unchanged_sources = String[]
    context = String[]
    
    for (i, source) in enumerate(result.sources)
        if !haskey(processor.tracked_sources, source)
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            processor.tracked_sources[source] = (processor.call_counter, result.context[i])
        elseif processor.tracked_sources[source][2] != result.context[i]
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            processor.tracked_sources[source] = (processor.call_counter, result.context[i])
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
    
    context_msg = isempty(context) ? "" : """
    Existing functions in other libraries:
    $(join(context, "\n"))
    """
    return context_msg
end

function AISH.cut_history!(processor::CodebaseContextProcessor, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (filepath, (msg_num, _)) in processor.tracked_files
        if msg_num < oldest_kept_message
            delete!(processor.tracked_files, filepath)
        end
    end
end

function AISH.cut_history!(processor::JuliaPackageContextProcessor, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (source, (msg_num, _)) in processor.tracked_sources
        if msg_num < oldest_kept_message
            delete!(processor.tracked_sources, source)
        end
    end
end

# Async Joiner implementation
function get_context(joiner::AsyncContextJoiner, creator::EasyContextCreatorV3, question, ai_state, shell_results)
    tasks = [
        @async get_context(processor, question, ai_state, shell_results)
        for processor in joiner.processors
    ]
    
    results = fetch.(tasks)
    
    # Join the results
    joined_context = join(filter(!isempty, results), "\n\n")
    
    # Cut history after processing contexts
    for processor in joiner.processors
        cut_history!(processor, joiner.keep)
    end
    
    # Cut conversation history
    conv = curr_conv(ai_state)
    cut_history!(conv, keep=joiner.keep)
    
    
    return joined_context
end

# Main prepare_user_message! function
function AISH.prepare_user_message!(ctx::EasyContextCreatorV3, ai_state, question, shell_results)
    conv = curr_conv(ai_state)
    
    # Use the AsyncContextJoiner to process and join contexts
    context = get_context(ctx.joiner, ctx, question, ai_state, shell_results)
    
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

    new_msg = """
    $context
    ## User question:
    $question
    """
    
    new_msg
end

