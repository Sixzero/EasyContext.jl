using Test
using EasyContext
using EasyContext: WorkspaceCTX, init_workspace_context, process_workspace_context
using EasyContext: get_chunks, NewlineChunker, FileChunk

@testset "WorkspaceCTX" begin
    # Test initialization
    @testset "Initialization" begin
        workspace_ctx = init_workspace_context([pwd()]; verbose=false)
        
        @test workspace_ctx isa WorkspaceCTX
        @test !isnothing(workspace_ctx.rag_pipeline)
        @test !isnothing(workspace_ctx.workspace)
        @test !isnothing(workspace_ctx.tracker_context)
        @test !isnothing(workspace_ctx.changes_tracker)
    end
    
    # Test processing with different queries
    @testset "Process Workspace Context" begin
        workspace_ctx = init_workspace_context([pwd()]; verbose=false)
        
        # Test with a query that should find results
        result, chunks, reranked = process_workspace_context(workspace_ctx, "workspace search")
        @test !isempty(result)
        @test !isnothing(chunks)
        @test !isnothing(reranked)
        
        # Test with a query that should find minimal or no results
        result_empty, _, _ = process_workspace_context(workspace_ctx, "xyznonexistentquery123456789")
        @test isempty(result_empty)
        
        # Test with disabled flag
        result_disabled, _, _ = process_workspace_context(workspace_ctx, "workspace search"; enabled=false)
        @test isempty(result_disabled)
    end
    
    # Test with empty chunks
    @testset "Empty Chunks" begin
        workspace_ctx = init_workspace_context([pwd()]; verbose=false)
        
        # Mock an empty workspace by creating a temporary directory
        mktempdir() do empty_dir
            empty_workspace_ctx = init_workspace_context([empty_dir]; verbose=false)
            result, _, _ = process_workspace_context(empty_workspace_ctx, "test query")
            @test isempty(result)
        end
    end
    
    # Test cd functionality
    @testset "Directory Change" begin
        workspace_ctx = init_workspace_context([pwd()]; verbose=false)
        current_dir = pwd()
        
        # Test that cd works with the workspace context
        cd(workspace_ctx) do
            @test pwd() == current_dir
        end
    end
end
;


