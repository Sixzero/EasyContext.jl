export process_workspace_context, init_workspace_context

import Base: write

@kwdef mutable struct WorkspaceCTX
    rag_pipeline::TwoLayerRAG          
    workspace::AbstractWorkspace
    tracker_context::Context           
    changes_tracker::ChangeTracker
end

struct WorkspaceCTXResult
    new_chunks::Vector{FileChunk}
    updated_chunks::Vector{FileChunk}
    cost::Threads.Atomic{Float64}
    elapsed::Float64
end

Base.write(io::IO, ::WorkspaceCTXResult) = nothing

Base.cd(f::Function, workspace_ctx::WorkspaceCTX) = cd(f, workspace_ctx.workspace)

# we want to globally track what is in the context and what is not.
const WorkspaceContext = Context{FileChunk}()
const WorkspaceChangeTracker = ChangeTracker{FileChunk}()

function init_workspace_context(project_paths::Vector{<:AbstractString}; 
    show_tokens=false, 
    verbose=true, 
    virtual_ws=nothing, 
    pipeline=EFFICIENT_PIPELINE())
    
    workspace = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    
    WorkspaceCTX(
        pipeline,
        workspace,
        WorkspaceContext,
        WorkspaceChangeTracker,
    )
end

function process_workspace_context(workspace_context::WorkspaceCTX, embedder_query; rerank_query=embedder_query, enabled=true, age_tracker=nothing, extractor=nothing, io::Union{IO, Nothing}=nothing,)
    !enabled || isempty(workspace_context.workspace) && return ("", nothing, nothing)
    
    start_time = time()
    
    file_chunks = RAG.get_chunks(NewlineChunker{FileChunk}(), workspace_context.workspace)
    isempty(file_chunks) && return ("", nothing, nothing)
    
    cost_tracker = Threads.Atomic{Float64}(0.0)
    file_chunks_reranked = search(workspace_context.rag_pipeline, file_chunks, embedder_query; rerank_query, cost_tracker)
    merged_file_chunks = merge!(workspace_context.tracker_context, file_chunks_reranked)
    
    !isnothing(extractor) && update_changes_from_extractor!(workspace_context.changes_tracker, extractor)
    scr_content = update_changes!(workspace_context.changes_tracker, merged_file_chunks)
    !isnothing(age_tracker) && register_changes!(age_tracker, workspace_context.changes_tracker)
    
    # Update time tracker with total time
    elapsed = time() - start_time
    
    isa(scr_content, String) && return ("", nothing, nothing)
    
    new_chunks, updated_chunks = get_filtered_chunks(workspace_context.changes_tracker, scr_content)
    result = WorkspaceCTXResult(new_chunks, updated_chunks, cost_tracker, elapsed)
    result_str = workspace_ctx_2_string(new_chunks, updated_chunks)
    !isnothing(io) && write(io, result)
    
    (result_str, file_chunks, file_chunks_reranked)
end

function update_changes_from_extractor!(changes_tracker, extractor)
    for task in values(extractor.tool_tasks)
        cb = fetch(task)
        !isa(cb, ModifyFileTool) && continue
        changes_tracker.changes[cb.file_path] = :UPDATED
        changes_tracker.content[cb.file_path] = cb.postcontent
    end
end

