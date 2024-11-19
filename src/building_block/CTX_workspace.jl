
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
Base.cd(f::Function, workspace::Workspace)        = !isempty(workspace.root_path)               ? cd(f, workspace.root_path)               : f()

function init_workspace_context(project_paths; show_tokens=false, verbose=true, index_logger_path="workspace_context_log", virtual_ws=nothing)
    workspace            = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    tracker_context      = Context()
    changes_tracker      = ChangeTracker()
    openai_embedder      = create_openai_embedder(cache_prefix="workspace")
    ws_simi_filterer     = create_combined_index_builder(openai_embedder, top_k=30)
    ws_reranker_filterer = ReduceRankGPTReranker(batch_size=30, model="gpt4om")
    
    index_logger = IndexLogger(index_logger_path)

    return WorkspaceCTX(workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, index_logger )
end

function process_workspace_context(workspace_context, ctx_question; age_tracker=nothing, extractor=nothing)
    workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, index_logger = workspace_context.workspace, workspace_context.tracker_context, workspace_context.changes_tracker, workspace_context.ws_simi_filterer, workspace_context.ws_reranker_filterer, workspace_context.index_logger
    scr_content = cd(workspace_context) do
        file_chunks = workspace(FullFileChunker()) 
        isempty(file_chunks) && return ""
        indexx = get_index(ws_simi_filterer, file_chunks)
        file_chunks_selected = ws_simi_filterer(indexx, ctx_question)
        file_chunks_reranked = ws_reranker_filterer(file_chunks_selected, ctx_question)
        merged_file_chunks = tracker_context(file_chunks_reranked)
        !isnothing(extractor) && update_changes_from_extractor!(changes_tracker, extractor)
        _scr_content = changes_tracker(merged_file_chunks)
        !isnothing(age_tracker) && age_tracker(changes_tracker)
        log_index(index_logger, indexx, ctx_question)
        return _scr_content
    end
    isa(scr_content,String) && return ""
    
    return workspace_ctx_2_string(changes_tracker, scr_content)
end

function update_changes_from_extractor!(changes_tracker, extractor)
    for cb in values(extractor.shell_results)
        if cb.type == :MODIFY
            changes_tracker.changes[cb.file_path] = :UPDATED
            changes_tracker.content[cb.file_path] = cb.postcontent
        end
    end
end

