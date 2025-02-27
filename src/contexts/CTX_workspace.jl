export process_workspace_context, init_workspace_context

import Base: write

@kwdef mutable struct WorkspaceCTX
    rag_pipeline::TwoLayerRAG          
    workspace::Workspace
    tracker_context::Context           
    changes_tracker::ChangeTracker
end

struct WorkspaceCTXResult
    content::String
end
Base.write(io::IO, ::WorkspaceCTXResult) = nothing

Base.cd(f::Function, workspace_ctx::WorkspaceCTX) = cd(f, workspace_ctx.workspace)

function init_workspace_context(project_paths; show_tokens=false, verbose=true, virtual_ws=nothing, model=["gem20f", "gem15f", "gpt4om"], top_k=50, top_n=12)
    workspace = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    embedder = create_cohere_embedder(cache_prefix="workspace")
    bm25 = BM25Embedder()
    topK = TopK([embedder, bm25]; top_k)
    reranker = ReduceGPTReranker(batch_size=30; top_n, model)
    
    WorkspaceCTX(
        TwoLayerRAG(; topK, reranker),
        workspace,
        Context{FileChunk}(),
        ChangeTracker{FileChunk}()
    )
end

function process_workspace_context(workspace_context::WorkspaceCTX, embedder_query; rerank_query=embedder_query, enabled=true, age_tracker=nothing, extractor=nothing, io::Union{IO, Nothing}=nothing)
    !enabled && return ("", nothing)
    
    file_chunks = get_chunks(FullFileChunker(), workspace_context.workspace)
    isempty(file_chunks) && return ("", nothing)
    
    file_chunks_reranked = search(workspace_context.rag_pipeline, file_chunks, embedder_query; rerank_query)
    merged_file_chunks = merge!(workspace_context.tracker_context, file_chunks_reranked)
    
    !isnothing(extractor) && update_changes_from_extractor!(workspace_context.changes_tracker, extractor)
    scr_content = update_changes!(workspace_context.changes_tracker, merged_file_chunks)
    !isnothing(age_tracker) && register_changes!(age_tracker, workspace_context.changes_tracker)
    
    isa(scr_content, String) && return ("", nothing)
    
    result = workspace_ctx_2_string(workspace_context.changes_tracker, scr_content)
    write(io, WorkspaceCTXResult(result))
    
    (result, file_chunks)
end

function update_changes_from_extractor!(changes_tracker, extractor)
    for task in values(extractor.tool_tasks)
        cb = fetch(task)
        !isa(cb, ModifyFileTool) && continue
        changes_tracker.changes[cb.file_path] = :UPDATED
        changes_tracker.content[cb.file_path] = cb.postcontent
    end
end

