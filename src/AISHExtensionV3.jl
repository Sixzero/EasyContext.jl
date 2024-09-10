using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, save_user_message, format_shell_results
import AISH


# Async Joiner
"""
    AsyncContextJoiner

A structure that manages multiple context processors and their execution.

Fields:
- `processors::Vector{AbstractContextProcessor}`: List of context processors
"""
@kwdef mutable struct AsyncContextJoiner
    processors::Vector{AbstractContextProcessor}
end

"""
    EasyContextCreatorV3 <: AbstractContextCreator

Main structure for EasyContext V3, managing context creation and processing.

Fields:
- `joiner::AsyncContextJoiner`: Manages multiple context processors
- `keep::Int`: Maximum number of messages to keep in history
- `max_messages::Int`: Threshold for triggering a history cut
"""
@kwdef mutable struct EasyContextCreatorV3 <: AbstractContextCreator
    joiner::AsyncContextJoiner = AsyncContextJoiner(
        processors=[
            CodebaseContextV2(),
            ShellContext(),
            # GoogleContext(),
            # JuliaPackageContext(),
            # PythonPackageContext(),
        ]
    )
    keep::Int = 10
    max_messages::Int = 16
end

"""
    AISH.get_cache_setting(creator::EasyContextCreatorV3, conv)

Determine caching settings based on conversation length.

Returns:
- `:all` if conversation length is below threshold
- `nothing` otherwise
"""
function AISH.get_cache_setting(creator::EasyContextCreatorV3, conv)
    if length(conv.messages) >= creator.max_messages - 2
        return nothing  # or :no_cache
    end
    return :all
end

function AISH.cut_history!(joiner::AsyncContextJoiner, keep::Int)
    for processor in joiner.processors
        cut_history!(processor, keep)
    end
end

# Async Joiner implementation
function get_context(joiner::AsyncContextJoiner, creator::EasyContextCreatorV3, question, ai_state, shell_results)
    tasks = [
        @async get_context(processor, question, ai_state, shell_results)
        for processor in joiner.processors
    ]
    
    results = fetch.(tasks)
    
    # Join the results with formatting
    joined_context = join([format_context_node(result) for result in results], "\n\n")
    
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
    
    # Check and cut history if necessary
    if length(conv.messages) >= ctx.max_messages
        cut_history!(ctx.joiner, ctx.keep)
        cut_history!(conv, keep=ctx.keep)
    end
    
    # Use the AsyncContextJoiner to process and join contexts
    context = get_context(ctx.joiner, ctx, question, ai_state, shell_results)
    
    codebase_ctx = """
    The codebase you are working on will be in user messages. 
    File contents will be wrapped in <Files NEW> and <Files UPDATED> tags.

    If a code has been updated or got some change they will be mentioned in the <Files UPDATED> section, and always this will represent the newest version of their file content. If something is not like you proposed and is not mentioned in the <Files UPDATED> section, it's probably because the change was partially accepted or not accepted, we might need to rethink our idea.
    """
    # Create system message (without file contents)
    if conv.system_message.content != SYSTEM_PROMPT(;ctx=codebase_ctx)
        conv.system_message = Message(timestamp=now(), role=:system, content=SYSTEM_PROMPT(;ctx=codebase_ctx))
        @info "System message updated!"
    end

    new_msg = """
    <Context>
    $context
    </Context>

    <UserQuestion>
    $question
    </UserQuestion>
    """
    
    return new_msg
end

