using Test
using EasyContext
using EasyContext: WorkspaceSearchTool, ToolTag, execute, result2string
using UUIDs

@testset "WorkspaceSearchTool" begin
    # Test constructor from ToolTag
    @testset "Constructor" begin
        cmd = ToolTag("WORKSPACE_SEARCH", "how does the search work", Dict("root_path" => pwd()))
        tool = WorkspaceSearchTool(cmd)
        
        @test tool.query == "how does the search work"
        @test !isnothing(tool.workspace_ctx)
        @test tool.result == ""
    end
    
    # Test execution
    @testset "Execution" begin
        # Create a tool with a specific query that should find results
        cmd = ToolTag("WORKSPACE_SEARCH", "workspace search tool", Dict("root_path" => pwd()))
        tool = WorkspaceSearchTool(cmd)
        
        # Execute the tool
        success = execute(tool; no_confirm=true)
        @test success == true
        @test !isempty(tool.result)
        
        # Test result formatting
        result_str = result2string(tool)
        @test occursin("Search results for: workspace search tool", result_str)
        
        # Test with a query that should return no results
        cmd_empty = ToolTag("WORKSPACE_SEARCH", "xyznonexistentquery123456789", Dict("root_path" => pwd()))
        tool_empty = WorkspaceSearchTool(cmd_empty)
        execute(tool_empty; no_confirm=true)
        result_empty = result2string(tool_empty)
        
        if isempty(tool_empty.result)
            @test occursin("No relevant code found", result_empty)
        end
    end
    
    # Test tool metadata
    @testset "Tool Metadata" begin
        @test toolname(WorkspaceSearchTool) == "WORKSPACE_SEARCH"
        @test tool_format(WorkspaceSearchTool) == :single_line
        @test stop_sequence(WorkspaceSearchTool) == STOP_SEQUENCE
        @test !isempty(get_description(WorkspaceSearchTool))
    end
end
