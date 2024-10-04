export process_workspace_context

function init_workspace_context(project_paths)
  workspace = WorkspaceLoader(project_paths)
  workspace_ctx = Context()
  ws_age = AgeTracker()
  ws_changes = ChangeTracker()
  ws_simi_filterer = create_combined_index_builder(top_k=30)
  ws_reranker_filterer = ReduceRankGPTReranker(batch_size=30, model="gpt4om")
  return (;workspace, workspace_ctx, ws_age, ws_changes, ws_simi_filterer, ws_reranker_filterer)
end

function process_workspace_context(workspace_context, ctx_question)
  (;workspace, workspace_ctx, ws_age, ws_changes, ws_simi_filterer, ws_reranker_filterer) = workspace_context
  file_chunks = workspace(FullFileChunker()) 
  index = get_index(ws_simi_filterer, file_chunks)
  file_chunks_selected = ws_simi_filterer(index, ctx_question)
  file_chunks_reranked = ws_reranker_filterer(file_chunks_selected, ctx_question)
  merged_file_chunks = workspace_ctx(file_chunks_reranked)
  ws_age(merged_file_chunks)
  state, scr_content = ws_changes(merged_file_chunks)
  return workspace_ctx_2_string(state, scr_content)
end

age!(workspace_context, conversation) = ageing!(workspace_context.ws_age, conversation, workspace_context.workspace_ctx, workspace_context.ws_changes)