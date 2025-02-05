export process_julia_context, init_julia_context


@kwdef mutable struct JuliaCTX
    rag_pipeline::TwoLayerRAG
    tracker_context::Context
    changes_tracker::ChangeTracker

    pkg_chunks::CachedLoader
end
struct JuliaCTXResult
    content::String
end
write(io::IO, ::JuliaCTXResult) = nothing

function init_julia_context(; 
    package_scope=:installed, 
    verbose=true, 
    excluded_packages=String[],
    model="dscode",
    top_k=50,
)
    # Initialize with nothing, will be lazily created on first use
    tracker_context = Context{SourceChunk}()
    changes_tracker = ChangeTracker{SourceChunk}(; verbose=verbose)

    embedder          = create_voyage_embedder(cache_prefix="juliapkgs")
    bm25              = BM25Embedder()
    topK              = TopK([embedder, bm25]; top_k)
    reranker          = ReduceGPTReranker(batch_size=40, top_n=10; model)
    rag_pipeline      = TwoLayerRAG(; topK, reranker)

    pkg_chunks = CachedLoader(loader=JuliaLoader(; excluded_packages=excluded_packages), memory=Dict{String,OrderedDict{String,String}}())

    return JuliaCTX(
        rag_pipeline,
        tracker_context,
        changes_tracker,
        pkg_chunks,
    )
end

function process_julia_context(julia_context::JuliaCTX, ctx_question; enabled=true, rerank_query=ctx_question, age_tracker=nothing, io::Union{IO, Nothing}=nothing)
    !enabled && return ("", nothing)
    rag_pipeline      = julia_context.rag_pipeline
    tracker_context   = julia_context.tracker_context
    changes_tracker   = julia_context.changes_tracker
    pkg_chunks        = julia_context.pkg_chunks

    src_chunks = pkg_chunks(SourceChunker()) # TODO remove functor workflow. also WHUT is this doing
    
    file_chunks_reranked = search(rag_pipeline, src_chunks, ctx_question)
    
    merged_file_chunks = merge!(tracker_context, file_chunks_reranked)
    scr_content = update_changes!(changes_tracker, merged_file_chunks)

    !isnothing(age_tracker) && age_tracker(changes_tracker)

    result = julia_ctx_2_string(changes_tracker, scr_content)
    write(io, JuliaCTXResult(result))
    # write_event!(io, "julia_context", result)
    
    return result, src_chunks
end
