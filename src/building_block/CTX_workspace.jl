export process_workspace_context, init_workspace_context

using EasyRAGStore: IndexLogger, log_index

function init_workspace_context(project_paths; verbose=true, index_logger_path="workspace_context_log", append_files=String[])
    workspace = WorkspaceLoader(project_paths; verbose, append_files)
    tracker_context = Context()
    changes_tracker = ChangeTracker()
    ws_simi_filterer = create_combined_index_builder(top_k=30)
    ws_reranker_filterer = ReduceRankGPTReranker(batch_size=30, model="gpt4om")
    formatter = workspace_ctx_2_string  # Default formatter
    
    index_logger = IndexLogger(index_logger_path)

    return (;workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, formatter, index_logger )
end

function process_workspace_context(workspace_context, ctx_question; age_tracker=nothing)
    (;workspace, tracker_context, changes_tracker, ws_simi_filterer, ws_reranker_filterer, formatter, index_logger) = workspace_context
    file_chunks = workspace(FullFileChunker()) 
    isempty(file_chunks) && return ""
    index = get_index(ws_simi_filterer, file_chunks)
    file_chunks_selected = ws_simi_filterer(index, ctx_question)
    file_chunks_reranked = ws_reranker_filterer(file_chunks_selected, ctx_question)
    merged_file_chunks = tracker_context(file_chunks_reranked)
    scr_content = changes_tracker(merged_file_chunks)
    !isnothing(age_tracker) && age_tracker(changes_tracker)
    
    # Log the index and question
    log_index(index_logger, index, ctx_question)
    
    return formatter(changes_tracker, scr_content)
end
