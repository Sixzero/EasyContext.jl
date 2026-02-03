export process_workspace_context, init_workspace_context

import Base: write

@kwdef mutable struct WorkspaceCTX
    rag_pipeline::AbstractRAGPipeline          
    workspace::AbstractWorkspace
    tracker_context::Context           
    changes_tracker::ChangeTracker
end

struct WorkspaceCTXResult{T <: AbstractChunk}
    new_chunks::Vector{T}
    updated_chunks::Vector{T}
    cost::Float64
    elapsed::Float64
end

Base.write(io::Base.TTY, ::WorkspaceCTXResult) = nothing

Base.cd(f::Function, workspace_ctx::WorkspaceCTX) = cd(f, workspace_ctx.workspace)

# we want to globally track what is in the context and what is not.
const WorkspaceContext = Context{FileChunk}()
const WorkspaceChangeTracker = ChangeTracker{FileChunk}()

function init_workspace_context(project_paths::Vector{<:AbstractString}; 
    show_tokens=false, 
    verbose=true, 
    virtual_ws=nothing, 
    pipeline=EFFICIENT_PIPELINE(),
    tracker_context::Context{FileChunk}=WorkspaceContext, 
    changes_tracker::ChangeTracker{FileChunk}=WorkspaceChangeTracker)
    
    workspace = Workspace(project_paths; virtual_ws, verbose, show_tokens)
    
    WorkspaceCTX(
        pipeline,
        workspace,
        tracker_context,
        changes_tracker,
    )
end

function process_workspace_context(workspace_context::WorkspaceCTX, embedder_query; rerank_query=embedder_query, enabled=true, source_tracker=nothing, io=nothing, query_images::Union{AbstractVector{<:AbstractString}, Nothing}=nothing, request_id=nothing)
    !enabled || isempty(workspace_context.workspace) && return ("", nothing, nothing, nothing)
    
    start_time = time()
    
    file_chunks = RAGTools.get_chunks(NewlineChunker{FileChunk}(), workspace_context.workspace)
    isempty(file_chunks) && return ("", nothing, nothing, nothing)
    
    cost_tracker = Threads.Atomic{Float64}(0.0)
    file_chunks_reranked = search(workspace_context.rag_pipeline, file_chunks, embedder_query; rerank_query, cost_tracker, query_images, request_id)
    merged_file_chunks = merge!(workspace_context.tracker_context, file_chunks_reranked)
    
    scr_content = update_changes!(workspace_context.changes_tracker, merged_file_chunks)
    !isnothing(source_tracker) && register_changes!(source_tracker, workspace_context.changes_tracker, workspace_context.tracker_context)
    
    # Update time tracker with total time
    elapsed = time() - start_time
    
    isa(scr_content, String) && return ("", nothing, nothing, nothing)
    
    new_chunks, updated_chunks = get_filtered_chunks(workspace_context.changes_tracker, scr_content)
    TYPE = eltype(new_chunks)
    result = WorkspaceCTXResult{TYPE}(new_chunks, updated_chunks, cost_tracker[], elapsed)
    result_str = workspace_ctx_2_string(new_chunks, updated_chunks)
    !isnothing(io) && write(io, result)
    
    (result_str, file_chunks, file_chunks_reranked, result)
end

