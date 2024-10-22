export process_julia_context, init_julia_context

using EasyRAGStore: IndexLogger, log_index

@kwdef mutable struct JuliaCTX
    voyage_embedder::EmbeddingIndexBuilder
    jl_simi_filter::EasyContext.CachedIndexBuilder{EasyContext.CombinedIndexBuilder}           
    jl_pkg_index
    tracker_context::Context
    changes_tracker::ChangeTracker
    jl_reranker_filterer
    index_logger::IndexLogger
end

function init_julia_context(; package_scope=:installed, verbose=true, index_logger_path="julia_context_log")
    voyage_embedder = create_voyage_embedder(model="voyage-code-2")
    jl_simi_filter = create_combined_index_builder(voyage_embedder; top_k=120)
    
    # Wrap the jl_simi_filter with CachedIndexBuilder
    cached_jl_simi_filter = CachedIndexBuilder(jl_simi_filter)
    
    # Use the provided package_scope
    julia_loader = CachedLoader(loader=JuliaLoader(package_scope=package_scope), memory=Dict{String,OrderedDict{String,String}}())(SourceChunker())
    
    jl_pkg_index = get_index(cached_jl_simi_filter, julia_loader)
    tracker_context = Context()
    changes_tracker = ChangeTracker(;need_source_reparse=false, verbose=verbose)
    jl_reranker_filterer = ReduceRankGPTReranker(batch_size=40, model="gpt4om")

    index_logger = IndexLogger(index_logger_path)

    return JuliaCTX(
        voyage_embedder,
        cached_jl_simi_filter,
        jl_pkg_index,
        tracker_context,
        changes_tracker,
        jl_reranker_filterer,
        index_logger,
    )
end

function process_julia_context(julia_context::JuliaCTX, ctx_question; age_tracker=nothing)
    jl_simi_filter       = julia_context.jl_simi_filter
    jl_pkg_index         = julia_context.jl_pkg_index
    tracker_context      = julia_context.tracker_context
    changes_tracker      = julia_context.changes_tracker
    jl_reranker_filterer = julia_context.jl_reranker_filterer
    index_logger         = julia_context.index_logger

    file_chunks_selected = jl_simi_filter(jl_pkg_index, ctx_question)
    file_chunks_reranked = jl_reranker_filterer(file_chunks_selected, ctx_question)
    merged_file_chunks = tracker_context(file_chunks_reranked)
    scr_content = changes_tracker(merged_file_chunks)
    
    !isnothing(age_tracker) && age_tracker(changes_tracker)
    
    # Log the index and question
    log_index(index_logger, jl_pkg_index, ctx_question)
    
    return julia_ctx_2_string(changes_tracker, scr_content)
end