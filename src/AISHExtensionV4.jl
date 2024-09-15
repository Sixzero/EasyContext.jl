module AISHExtensionV4

using AISH
using Dates
using ..EasyContext
using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
import AISH: AbstractContextCreator, prepare_user_message!, get_cache_setting

export get_context, cut_history!, AISHExtensionV4, Pipe

# Define the Pipe struct
struct Pipe
    processors::Vector{Any}
end

# Define a functor for Pipe
function (pipe::Pipe)(input)
    for processor in pipe.processors
        input = processor(input)
    end
    return input
end

# List of ctx processor pipelines
@kwdef struct PipedContextProcessor
    processors::Vector{Pipe}=[
        Pipe([ShellContext()]),
        Pipe([
            QuestionAccumulator(),
            CodebaseContextV3(),
            ContextNode(title="Codebase", element="File"),
        ]),
        Pipe([
            JuliaPackageContext(),
            EmbeddingIndexBuilder(),
            ReduceRankGPTReranker(),
            ContextNode(title="Functions", element="Function")
        ])
    ]
end

@kwdef mutable struct AISHExtensionV4 <: AbstractContextCreator
    processor::PipedContextProcessor=PipedContextProcessor()
    keep::Int = 9
    max_messages::Int = 17
end

function (pcp::PipedContextProcessor)(question::String, ai_state=nothing, shell_results=nothing)
    context = ""
    for pipe in pcp.processors
        res = pipe(question)
        context *= res
    end
    return context::String
end

function get_context(pcp::PipedContextProcessor, question::String, ai_state=nothing, shell_results=nothing)
    return pcp(question, ai_state, shell_results)
end

function cut_history!(pcp::PipedContextProcessor, keep::Int)
    for pipe in pcp.processors
        for processor in pipe.processors
            if applicable(AISH.cut_history!, processor, keep)
                AISH.cut_history!(processor, keep)
            end
        end
    end
end

function get_cache_setting(creator::AISHExtensionV4, conv)
    if length(conv.messages) >= creator.max_messages - 2
        return nothing
    end
    return :all
end

function prepare_user_message!(ctx::AISHExtensionV4, ai_state, question, shell_results)
    conv = AISH.curr_conv(ai_state)
    
    # Check and cut history if necessary
    if length(conv.messages) >= ctx.max_messages
        AISH.cut_history!(conv, keep=ctx.keep)
        cut_history!(ctx.processor, ctx.keep)
    end
    
    conv = curr_conv(ai_state)
    # Update CodebaseContextV3 project_paths
    for processor in ctx.processor.processors
        if processor isa CodebaseContextV3
            processor.project_paths = conv.rel_project_paths
            break
        end
    end
    
    # Process context
    context = get_context(ctx.processor, question, ai_state, shell_results)

    codebase_ctx = """
    The codebase you are working on will be in user messages. 
    File contents will be wrapped in <Codebase> and </Codebase> tags.
    Function definitions in other existing intalled packages will be wrapped in <Function> and </Function> tags.

    If a code has been updated or got some change they will be mentioned in the <Codebase UPDATED> section, and always this will represent the newest version of their file content. If something is not like you proposed and is not mentioned in the <Codebase UPDATED> section, it's probably because the change was partially accepted or not accepted, we might need to rethink our idea.
    """
    
    # Update system message if necessary
    if conv.system_message.content != AISH.SYSTEM_PROMPT(;ctx=codebase_ctx)
        conv.system_message = AISH.Message(timestamp=now(), role=:system, content=AISH.SYSTEM_PROMPT(;ctx=codebase_ctx))
        @info "System message updated!"
    end

    # Prepare the new message
    new_msg = """
    $context
    
    <UserQuestion>
    $question
    </UserQuestion>
    """
    
    return new_msg
end

end # module

