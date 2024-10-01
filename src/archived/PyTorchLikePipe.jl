using AISH
using Dates
using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
import AISH: prepare_user_message!, get_cache_setting, genid

export ProModel, AbstractPyTorchLikeForward

abstract type AbstractPyTorchLikeForward end

# @kwdef mutable struct ConversationCTX
#     max_history::Int = 12
#     keep_history::Int = 6
#     conv::Vector{AbstractChatMessage} = []
#     sys_msg::SystemMessage=SystemMessage()
# end

# function (cp::ConversationCTX)(input)
#     conv = cp.conv
#     if length(conv) > cp.max_history
#         conv = conv[end-cp.keep_history+1:end]
#     end
#     push!(conv, UserMessage(input))
#     saveUserMsg(model.conversation_processor, input)
#     need_cache = (length(conv)+1>cp.max_history) ? nothing : :last
#     return [cp.sys_msg, conv...], need_cache
# end

@kwdef mutable struct StreamingLLMProcessor
    model::String
    extractor::CodeBlockExtractor = CodeBlockExtractor()
    state::AISH.AIState
end

function (slp::StreamingLLMProcessor)(conv; on_chunk=c->c, cache=:last)
    clearline()
    print("\e[32mProcessing... \e[0m")
    reset!(slp.extractor)
    channel = AISH.ai_stream_safe(conv, printout=false, cache=cache)
    msg, user_meta, ai_meta = AISH.process_stream(channel, 
        on_meta_usr=meta->(clearline();println("\e[32mUser message: \e[0m$(AISH.format_meta_info(meta))"); print("\e[36m¬ \e[0m")), 
        on_text=chunk->begin
                on_chunk(chunk, )
                print(chunk)
        end, 
        on_meta_ai=meta->println("\n\e[32mAI message: \e[0m$(AISH.format_meta_info(meta))"))
    println("")
    return msg, user_meta, ai_meta
end

function on_text(chunk::String, extractor::CodeBlockExtractor)
    print(chunk)
    extract_and_preprocess_shell_scripts(chunk, extractor)
end

@kwdef struct ProModel <: AbstractPyTorchLikeForward
    project_paths::Vector{String} = String[]
    state::NamedTuple = (;)
    conversation_processor::ConversationCTX
    shell_extractor::CodeBlockExtractor
    shell_context::ContextNode = ContextNode(tag="ShellRunResults", element="sh_script")
    codebase_context::ContextNode = ContextNode(tag="Codebase", element="File")
    package_context::ContextNode = ContextNode(tag="Functions", element="Function")
end

function (model::ProModel)(question::AbstractString)
    # Async processing
    context_tasks = Dict(
        :shell => @async begin
            shell_results = ShellContext()(question, model.state.ai_state, model.shell_extractor)
            format_shell_results_to_context(model.shell_context, shell_results)
        end,
        :codebase => @async begin
            question_acc = QuestionCTX()(question)
            codebase = CodebaseContextV3(project_paths=model.project_paths)(question_acc)
            reranked = ReduceRankGPTReranker(batch_size=30, model="gpt4om")(codebase)
            model.codebase_context(reranked)
        end,
        :package => @async begin
            question_acc = QuestionCTX()(question)
            package = JuliaPackageContext()(question_acc)
            embedded = EmbeddingIndexBuilder()(package)
            reranked = ReduceRankGPTReranker(batch_size=40)(embedded)
            model.package_context(reranked)
        end
    )

    # Wait for all tasks and combine contexts
    combined_context = """
    $(fetch(ctx_shell))

    $(fetch(ctx_codebase))

    $(fetch(ctx_package))

    <Question>
    $question
    </Question>
    """
    sys_msg_ext = ""
    sys_msg_ext *= get_processor_description(:ShellResults, model.shell_context)
    sys_msg_ext *= get_processor_description(:CodebaseContextV3, model.codebase_context)
    sys_msg_ext *= get_processor_description(:JuliaPackageContext, model.package_context)
    # Process through conversation processor and generate response
    processed_input, cache = model.conversation_processor(combined_context)
    
    streaming_llm = StreamingLLMProcessor(processed_input, model="claude", extractor=model.shell_extractor, cache=cache)
    response, user_meta, ai_meta = streaming_llm(processed_input)
    
    saveAiMsg(model.conversation_processor, response)

    return response, user_meta, ai_meta
end

function saveUserMsg(cp::ConversationCTX, msg::AbstractString)
    AISH.add_n_save_user_message!(cp.ai_state, msg)
end

function saveAiMsg(cp::ConversationCTX, msg::AbstractString)
    push!(cp.conv, AIMessage(msg))
    AISH.add_n_save_ai_message!(cp.ai_state, msg)
end
