module AISHExtensionV4

using AISH
using Dates
using ..EasyContext
using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
import AISH: AbstractContextCreator, prepare_user_message!, get_cache_setting

export get_context, cut_history!, AISHExtensionV4, Pipe, get_processor_description, generate_codebase_ctx

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
        Pipe([ShellContext(), ContextNode(tag="ShellRunResults", element="sh_output")]),
        Pipe([
            QuestionAccumulator(),
            CodebaseContextV3(),
            ContextNode(tag="Codebase", element="File"),
        ]),
        Pipe([
            JuliaPackageContext(),
            EmbeddingIndexBuilder(),
            ReduceRankGPTReranker(),
            ContextNode(tag="Functions", element="Function")
        ])
    ]
end

@kwdef mutable struct AISHExtensionV4 <: AbstractContextCreator
    processor::PipedContextProcessor=PipedContextProcessor()
    keep::Int = 9
    max_messages::Int = 17
end

function get_processor_description(processor::Any, context_node::Union{ContextNode, Nothing}=nothing)
    if isnothing(context_node)
        return ""  # Default empty description for unknown processors without a context node
    end
    return "$(processor) results will be wrapped in <$(context_node.tag)> and </$(context_node.tag)> tags, with individual elements wrapped in <$(context_node.element)> and </$(context_node.element)> tags."
end

function get_processor_description(::QuestionAccumulator, context_node::Union{ContextNode, Nothing}=nothing)
    return ""
end

function get_processor_description(::CodebaseContextV3, context_node::Union{ContextNode, Nothing}=nothing)
    if isnothing(context_node)
        return "The codebase you are working on will be in user messages."
    end
    return "The codebase you are working on will be wrapped in <$(context_node.tag)> and </$(context_node.tag)> tags, with individual files chunks wrapped in <$(context_node.element)> and </$(context_node.element)> tags."
end

function get_processor_description(::JuliaPackageContext, context_node::Union{ContextNode, Nothing}=nothing)
    if isnothing(context_node)
        return "Function definitions in other existing installed packages will be included."
    end
    return "Function definitions in other existing installed packages will be wrapped in <$(context_node.tag)> and </$(context_node.tag)> tags, with individual functions wrapped in <$(context_node.element)> and </$(context_node.element)> tags."
end

function get_processor_description(::ShellContext, context_node::Union{ContextNode, Nothing}=nothing)
    if isnothing(context_node)
        return "Shell command results will be included."
    end
    return "Shell command results will be wrapped in <ShellRunResults> and </ShellRunResults> tags, the perviously requested shell script (shortened just for readability) and is in <sh_script> and </sh_script> tags, the sh run output is in <sh_output> and </sh_output> tags."
end

function generate_codebase_ctx(pcp::PipedContextProcessor)
    descriptions = String[]
    
    for pipe in pcp.processors
        context_node = last(pipe.processors) isa ContextNode ? last(pipe.processors) : nothing
        for processor in pipe.processors
            if !(processor isa ContextNode)  # Skip ContextNode in description generation
                description = get_processor_description(processor, context_node)
                if !isempty(description)
                    push!(descriptions, description)
                end
            end
        end
    end
    
    # Add the standard message about code updates
    push!(descriptions, """
    If a code has been updated or got some change they will be mentioned in the <Codebase UPDATED> section, and always this will represent the newest version of their file content. If something is not like you proposed and is not mentioned in the <Codebase UPDATED> section, it's probably because the change was partially accepted or not accepted, we might need to rethink our idea.
    """)
    
    return join(unique(descriptions), "\n\n")
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
    
    # Update CodebaseContextV3 project_paths
    for pipe in ctx.processor.processors
        for processor in pipe.processors
            if processor isa CodebaseContextV3
                processor.project_paths = conv.rel_project_paths
                break
            end
        end
    end
    
    # Process context
    context = get_context(ctx.processor, question, ai_state, shell_results)

    # Generate dynamic codebase_ctx
    codebase_ctx = generate_codebase_ctx(ctx.processor)
    
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

