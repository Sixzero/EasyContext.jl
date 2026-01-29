using Test
using EasyContext
using EasyContext: WorkspaceSearchTool
using ToolCallFormat: ParsedCall, ParsedValue, execute, result2string, create_tool
using UUIDs

@testset "WorkspaceSearchTool" begin
    # Test constructor from ParsedCall
    @testset "Constructor" begin
        call = ParsedCall(
            name="workspace_search",
            kwargs=Dict("query" => ParsedValue("how does the search work"))
        )
        tool = create_tool(WorkspaceSearchTool, call)

        @test tool.query == "how does the search work"
        @test tool.result == ""
    end

    # Test execution
    @testset "Execution" begin
        # Create a tool with a specific query that should find results
        call = ParsedCall(
            name="workspace_search",
            kwargs=Dict("query" => ParsedValue("workspace search tool"))
        )
        tool = create_tool(WorkspaceSearchTool, call)

        # Note: Without workspace_ctx, execution may fail
        # This test is mainly for parsing/construction
        @test tool.query == "workspace search tool"
    end

    # Test tool metadata
    @testset "Tool Metadata" begin
        @test toolname(WorkspaceSearchTool) == "workspace_search"
        @test !isempty(get_description(WorkspaceSearchTool))
    end
end
