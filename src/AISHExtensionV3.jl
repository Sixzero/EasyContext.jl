using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, save_user_message, format_shell_results
import AISH

include("contexts/ContextProcessors.jl")

# Async Joiner
@kwdef mutable struct AsyncContextJoiner
    processors::Vector{AbstractContextProcessor}
    keep::Int = 10 # the max length history should be kept
    max_messages::Int = 16 # the threshold for triggering a cut
end

@kwdef mutable struct EasyContextCreatorV3 <: AbstractContextCreator
    joiner::AsyncContextJoiner = AsyncContextJoiner(
        processors=[
            CodebaseContextV2(),
            ShellContext(),
            # GoogleContext(),
            # JuliaPackageContext(),
        ]
    )
end

function AISH.get_cache_setting(creator::EasyContextCreatorV3, conv)
    if length(conv.messages) >= creator.joiner.max_messages - 2
        return nothing  # or :no_cache
    end
    return :all
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
    conv = curr_conv(ai_state)
    if length(conv.messages) >= joiner.max_messages
        for processor in joiner.processors
            cut_history!(processor, joiner.keep)
        end
        cut_history!(conv, keep=joiner.keep)
    end

    # Increment call_counter for all processors
    for processor in joiner.processors
        if hasproperty(processor, :call_counter)
            processor.call_counter += 2
        end
    end
    
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

