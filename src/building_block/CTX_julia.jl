export process_julia_context, init_julia_context

function init_julia_context(;verbose=true, package_scope::Symbol=:installed)
    voyage_embedder = create_voyage_embedder(model="voyage-code-2")
    jl_simi_filter = create_combined_index_builder(voyage_embedder; top_k=120)
    
    # Wrap the jl_simi_filter with CachedIndexBuilder
    cached_jl_simi_filter = CachedIndexBuilder(jl_simi_filter)
    
    # Use the provided package_scope
    julia_loader = CachedLoader(loader=JuliaLoader(package_scope=package_scope), memory=Dict{String,OrderedDict{String,String}}())
    
    jl_pkg_index = get_index(cached_jl_simi_filter, julia_loader(SourceChunker()))
    tracker_context = Context()
    changes_tracker = ChangeTracker(;need_source_reparse=false, verbose=verbose)
    jl_reranker_filterer = ReduceRankGPTReranker(batch_size=40, model="gpt4om")
    return (;voyage_embedder, jl_simi_filter=cached_jl_simi_filter, jl_pkg_index, tracker_context, changes_tracker, jl_reranker_filterer)
end

function process_julia_context(julia_context, ctx_question; age_tracker=nothing)
    (;jl_simi_filter, jl_pkg_index, tracker_context, changes_tracker, jl_reranker_filterer) = julia_context

    formatter = haskey(julia_context, :formatter) ? julia_context.formatter : julia_ctx_2_string

    file_chunks_selected = jl_simi_filter(jl_pkg_index, ctx_question)
    file_chunks_reranked = jl_reranker_filterer(file_chunks_selected, ctx_question)
    merged_file_chunks = tracker_context(file_chunks_reranked)
    scr_content = changes_tracker(merged_file_chunks)
    
    !isnothing(age_tracker) && age_tracker(changes_tracker)
    return formatter(changes_tracker, scr_content)
end
