
function init_julia_context()
  voyage_embedder = create_voyage_embedder(model="voyage-code-2")
  jl_simi_filter = create_combined_index_builder(voyage_embedder; top_k=120)
  jl_pkg_index = get_index(jl_simi_filter, CachedLoader(loader=JuliaLoader())(SourceChunker()))
  julia_ctx = Context()
  jl_age! = AgeTracker()
  jl_changes = ChangeTracker(;need_source_reparse=false)
  jl_reranker_filterer = ReduceRankGPTReranker(batch_size=40, model="gpt4om")
  return (;voyage_embedder, jl_simi_filter, jl_pkg_index, julia_ctx, jl_age!, jl_changes, jl_reranker_filterer)
end

function process_julia_context(julia_context, ctx_question)
  jl_simi_filter, jl_pkg_index, julia_ctx, jl_age!, jl_changes, jl_reranker_filterer = julia_context
  file_chunks_selected = jl_simi_filter(jl_pkg_index, ctx_question)
  file_chunks_reranked = jl_reranker_filterer(file_chunks_selected, ctx_question)
  merged_file_chunks = julia_ctx(file_chunks_reranked)
  jl_age!(merged_file_chunks, max_history=5, refresh_these=file_chunks_reranked)
  state, scr_content = jl_changes(merged_file_chunks)
  return julia_ctx_2_string(state, scr_content)
end
