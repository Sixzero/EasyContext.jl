export process_julia_context, init_julia_context

using EasyRAGStore: IndexLogger, log_index

@kwdef mutable struct JuliaCTX
    jl_simi_filter::EasyContext.CachedIndexBuilder{EasyContext.CombinedIndexBuilder}           
    jl_pkg_index::Union{Task, Nothing}
    tracker_context::Context
    changes_tracker::ChangeTracker
    jl_reranker_filterer
    index_logger::IndexLogger
end

function init_julia_context(; 
    package_scope=:installed, 
    verbose=true, 
    index_logger_path="julia_context_log",
    excluded_packages=String[]
)
    voyage_embedder = create_voyage_embedder(model="voyage-code-2", cache_prefix="juliapkgs")
    jl_simi_filter = create_combined_index_builder(voyage_embedder; top_k=120)
    
    # Wrap the jl_simi_filter with CachedIndexBuilder
    cached_jl_simi_filter = CachedIndexBuilder(jl_simi_filter)

    # Initialize with nothing, will be lazily created on first use
    jl_pkg_index = nothing
    tracker_context = Context()
    changes_tracker = ChangeTracker(;need_source_reparse=false, verbose=verbose)
    jl_reranker_filterer = ReduceRankGPTReranker(batch_size=40, top_n=10, model="gpt4om")

    index_logger = IndexLogger(index_logger_path)

    return JuliaCTX(
        cached_jl_simi_filter,
        jl_pkg_index,
        tracker_context,
        changes_tracker,
        jl_reranker_filterer,
        index_logger,
    )
end

function process_julia_context(enabled, julia_context::JuliaCTX, ctx_question; age_tracker=nothing, io::Union{IO, Nothing}=nothing)
    !enabled && return ""
    jl_simi_filter       = julia_context.jl_simi_filter
    jl_pkg_index         = julia_context.jl_pkg_index
    tracker_context      = julia_context.tracker_context
    changes_tracker      = julia_context.changes_tracker
    jl_reranker_filterer = julia_context.jl_reranker_filterer
    index_logger         = julia_context.index_logger

    # Lazy initialization of the index if not yet created
    if isnothing(jl_pkg_index)
        # Use the provided package_scope - need to recreate loader here
        julia_loader = CachedLoader(loader=JuliaLoader(; excluded_packages=excluded_packages), memory=Dict{String,OrderedDict{String,String}}())(SourceChunker())
        julia_context.jl_pkg_index = @async_showerr get_index(jl_simi_filter, julia_loader)
    end
    jl_pkg_index = julia_context.jl_pkg_index

    index::Union{Vector{RAG.AbstractChunkIndex}, RAG.AbstractChunkIndex} = fetch(jl_pkg_index)
    file_chunks_selected = jl_simi_filter(index, ctx_question)
    @time "rerank" file_chunks_reranked = jl_reranker_filterer(file_chunks_selected, ctx_question)
    merged_file_chunks = tracker_context(file_chunks_reranked)
    scr_content = changes_tracker(merged_file_chunks)

    !isnothing(age_tracker) && age_tracker(changes_tracker)

    # Log the index and question
    @time "index_logging" log_index(index_logger, index, ctx_question)

    result = julia_ctx_2_string(changes_tracker, scr_content)
    
    write_event!(io, "julia_context", result)
    
    return result
end