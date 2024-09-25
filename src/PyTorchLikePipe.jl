using AISH
using Dates
using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
import AISH: prepare_user_message!, get_cache_setting, genid

export ProModel, AbstractPyTorchLikeForward

abstract type AbstractPyTorchLikeForward end

@kwdef mutable struct ConversationProcessor
    ai_state::AISH.AIState
    max_history::Int = 10
end

function (cp::ConversationProcessor)(input)
    conv = AISH.curr_conv(cp.ai_state)
    if length(conv.messages) > cp.max_history
        AISH.cut_history!(conv, keep=cp.max_history)
    end
    return input
end

@kwdef mutable struct StreamingLLMProcessor
    model::String
    extractor::CodeBlockExtractor = CodeBlockExtractor()
    state::AISH.AIState
end

function (slp::StreamingLLMProcessor)(input)
    clearline()
    print("\e[32mProcessing... \e[0m")
    cache = get_cache_setting(slp.state.contexter, AISH.curr_conv(slp.state))
    channel = AISH.ai_stream_safe(slp.state, printout=false, cache=cache) 
    msg, user_meta, ai_meta = AISH.process_stream(channel, 
        on_meta_usr=meta->(clearline();println("\e[32mUser message: \e[0m$(AISH.format_meta_info(meta))"); AISH.update_last_user_message_meta(slp.state, meta); print("\e[36m¬ \e[0m")), 
        on_text=chunk->on_text(chunk, slp.extractor), 
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
    conversation_processor::ConversationProcessor
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
            question_acc = QuestionAccumulatorProcessor()(question)
            codebase = CodebaseContextV3(project_paths=model.project_paths)(question_acc)
            reranked = ReduceRankGPTReranker(batch_size=30, model="gpt4om")(codebase)
            model.codebase_context(reranked)
        end,
        :package => @async begin
            question_acc = QuestionAccumulatorProcessor()(question)
            package = JuliaPackageContext()(question_acc)
            embedded = EmbeddingIndexBuilder()(package)
            reranked = ReduceRankGPTReranker(batch_size=40)(embedded)
            model.package_context(reranked)
        end
    )

    # Wait for all tasks and combine contexts
    combined_context = """
    $(fetch(context_tasks[:shell]))

    $(fetch(context_tasks[:codebase]))

    $(fetch(context_tasks[:package]))

    <Question>
    $question
    </Question>
    """

    # Process through conversation processor and generate response
    saveUserMsg(model.conversation_processor, combined_context)
    processed_input = model.conversation_processor(combined_context)
    
    streaming_llm = StreamingLLMProcessor(model="claude", extractor=model.shell_extractor, state=model.state.ai_state)
    response, user_meta, ai_meta = streaming_llm(processed_input)
    
    saveAiMsg(model.conversation_processor, response)

    return response, user_meta, ai_meta
end

function saveUserMsg(cp::ConversationProcessor, msg::AbstractString)
    AISH.add_n_save_user_message!(cp.ai_state, msg)
end

function saveAiMsg(cp::ConversationProcessor, msg::AbstractString)
    AISH.add_n_save_ai_message!(cp.ai_state, msg)
end
