export process_workspace_context, init_workspace_context

using EasyRAGStore: IndexLogger, log_index


@kwdef mutable struct WorkspaceCTX
    workspace::Workspace
    tracker_context::Context           
    changes_tracker::ChangeTracker
    ws_simi_filterer::CombinedIndexBuilder
    ws_reranker_filterer
    index_logger::IndexLogger
end
Base.cd(f::Function, workspace_ctx::WorkspaceCTX) = cd(f, workspace_ctx.workspace)

function init_workspace_context(project_paths; show_tokens=false, verbose=true, index_logger_path="workspace_context_log", virtual_ws=nothing, model="gpt4om")
    workspace            = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    tracker_context      = Context()
    changes_tracker      = ChangeTracker()
    # openai_embedder      = create_voyage_embedder(cache_prefix="workspace")
    openai_embedder      = create_openai_embedder(cache_prefix="workspace")
    ws_simi_filterer     = create_combined_index_builder(openai_embedder, top_k=50)
    ws_reranker_filterer = ReduceRankGPTReranker(batch_size=30, top_n=12; model)
    
    index_logger = IndexLogger(index_logger_path)

    return WorkspaceCTX(workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, index_logger )
end

function process_workspace_context(workspace_context, ctx_question; age_tracker=nothing, extractor=nothing, io::Union{IO, Nothing}=nothing)
    workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, index_logger = workspace_context.workspace, workspace_context.tracker_context, workspace_context.changes_tracker, workspace_context.ws_simi_filterer, workspace_context.ws_reranker_filterer, workspace_context.index_logger
    @time "the cd" scr_content = cd(workspace_context) do
        file_chunks = workspace(FullFileChunker()) 
        isempty(file_chunks) && return ""
        @time "indexgetting" indexx = get_index(ws_simi_filterer, file_chunks)
        @time "rag filter" file_chunks_selected = ws_simi_filterer(indexx, ctx_question)
        @time "rerank" file_chunks_reranked = ws_reranker_filterer(file_chunks_selected, ctx_question)
        merged_file_chunks = tracker_context(file_chunks_reranked)
        !isnothing(extractor) && update_changes_from_extractor!(changes_tracker, extractor)
        _scr_content = changes_tracker(merged_file_chunks)
        !isnothing(age_tracker) && age_tracker(changes_tracker)
        log_index(index_logger, indexx, ctx_question)
        return _scr_content
    end
    isa(scr_content,String) && return ""
    
    result = workspace_ctx_2_string(changes_tracker, scr_content)
    write_event!(io, "workspace_context", result)
    
    return result
end

function update_changes_from_extractor!(changes_tracker, extractor)
    for task in values(extractor.tool_tasks)
        cb = fetch(task)
        !isa(cb, ModifyFileTool) && continue
        changes_tracker.changes[cb.file_path] = :UPDATED
        changes_tracker.content[cb.file_path] = cb.postcontent
    end
end

