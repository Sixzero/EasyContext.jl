export process_workspace_context, init_workspace_context


@kwdef mutable struct WorkspaceCTX
    rag_pipeline::TwoLayerRAG          
    workspace::Workspace
    tracker_context::Context           
    changes_tracker::ChangeTracker
end

struct WorkspaceCTXResult
    content::String
end
write(io::IO, ::WorkspaceCTXResult) = nothing

Base.cd(f::Function, workspace_ctx::WorkspaceCTX) = cd(f, workspace_ctx.workspace)

function init_workspace_context(project_paths; show_tokens=false, verbose=true, virtual_ws=nothing, model="gpt4om", top_k=50,top_n=12)
    workspace            = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    tracker_context      = Context{FileChunk}()
    changes_tracker      = ChangeTracker{FileChunk}()
    # embedder             = create_openai_embedder(cache_prefix="workspace")
    embedder             = create_voyage_embedder(cache_prefix="workspace")
    bm25                 = BM25Embedder()
    topK                 = TopK([embedder, bm25]; top_k)
    reranker             = ReduceGPTReranker(batch_size=30; top_n, model)
    rag_pipeline         = TwoLayerRAG(; topK, reranker)
    
    return WorkspaceCTX(
        rag_pipeline,
        workspace, 
        tracker_context, 
        changes_tracker, 
    )
end

function process_workspace_context(workspace_context, embedder_query; rerank_query=embedder_query, enabled=true, age_tracker=nothing, extractor=nothing, io::Union{IO, Nothing}=nothing)
    !enabled && return ("", nothing)
    rag_pipeline, workspace, tracker_context, changes_tracker = workspace_context.rag_pipeline, workspace_context.workspace, workspace_context.tracker_context, workspace_context.changes_tracker
    # @time "the cd" scr_content = cd(workspace_context) do
    file_chunks = get_workspace_chunks(workspace, FullFileChunker()) 
    isempty(file_chunks) && return ("", nothing)
    @time "search" file_chunks_reranked = search(rag_pipeline, file_chunks, embedder_query)

    merged_file_chunks = merge!(tracker_context, file_chunks_reranked)
    !isnothing(extractor) && update_changes_from_extractor!(changes_tracker, extractor)
    scr_content = update_changes!(changes_tracker, merged_file_chunks)
    !isnothing(age_tracker) && age_tracker(changes_tracker)
    # return scr_content
    # end
    isa(scr_content,String) && return ("", nothing)

    result = workspace_ctx_2_string(changes_tracker, scr_content)
    write(io, WorkspaceCTXResult(result))

    return result, file_chunks
end

function update_changes_from_extractor!(changes_tracker, extractor)
    for task in values(extractor.tool_tasks)
        cb = fetch(task)
        !isa(cb, ModifyFileTool) && continue
        changes_tracker.changes[cb.file_path] = :UPDATED
        changes_tracker.content[cb.file_path] = cb.postcontent
    end
end

