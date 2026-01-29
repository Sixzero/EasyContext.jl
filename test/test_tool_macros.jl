# test_tool_macros.jl - Tests for @tool macro

using Test
using EasyContext: AbstractTool, @tool
using EasyContext: get_description, toolname, get_tool_schema, execute, result2string
using ToolCallFormat: CONCISE, PYTHON, MINIMAL, TYPESCRIPT
using UUIDs: UUID, uuid4

@testset "ToolMacros" begin

    @testset "Passive tools (no params)" begin
        @tool TestReasonTool "ReasonTool" "Store reasoning"
        @tool TestTextTool "TextTool" "Store text" []

        @test toolname(TestReasonTool) == "ReasonTool"
        @test toolname(TestTextTool) == "TextTool"

        tool = TestReasonTool()
        @test tool.id isa UUID
        @test tool.content == ""
        @test toolname(tool) == "ReasonTool"
    end

    @testset "@tool with params" begin
        # Simple tool - string params
        @tool TestCatFileTool "cat_file" "Read file contents" [
            (:path, "string", "File path to read", true, nothing),
            (:limit, "integer", "Max lines to read", false, nothing),
            (:offset, "integer", "Start line", false, nothing),
        ] (tool; kwargs...) -> begin
            tool.result = "Read $(tool.path)"
        end

        @test toolname(TestCatFileTool) == "cat_file"

        tool = TestCatFileTool(path="/tmp/test.txt")
        @test tool.path == "/tmp/test.txt"
        @test tool.limit === nothing
        @test tool.offset === nothing

        # Test execute
        execute(tool)
        @test tool.result == "Read /tmp/test.txt"
        @test result2string(tool) == "Read /tmp/test.txt"
    end

    @testset "@tool with codeblock" begin
        @tool TestModifyFileTool "modify_file" "Modify file with search/replace" [
            (:path, "string", "File path", true, nothing),
            (:changes, "codeblock", "Search and replace blocks", true, nothing),
        ] (tool; kwargs...) -> begin
            tool.result = "Modified $(tool.path)"
        end

        @test toolname(TestModifyFileTool) == "modify_file"

        schema = get_tool_schema(TestModifyFileTool)
        @test schema.name == "modify_file"
        @test length(schema.params) == 2
        @test schema.params[1].type == "string"
        @test schema.params[2].type == "codeblock"
    end

    @testset "@tool with custom result" begin
        @tool TestSearchTool "search" "Search files" [
            (:query, "string", "Search pattern", true, nothing),
            (:max_results, "integer", "Max results", false, 100),
        ] (
            (tool; kwargs...) -> begin tool.result = "Found files" end
        ) (
            (tool) -> "Search for '$(tool.query)':\n$(tool.result)"
        )

        tool = TestSearchTool(query="test")
        @test tool.max_results == 100  # default value

        execute(tool)
        @test result2string(tool) == "Search for 'test':\nFound files"
    end

    @testset "CallStyle support" begin
        @tool TestStyleTool "style_test" "Test CallStyle" [
            (:name, "string", "Name parameter", true, nothing),
        ]

        desc_default = get_description(TestStyleTool)
        desc_python = get_description(TestStyleTool, PYTHON)
        desc_concise = get_description(TestStyleTool, CONCISE)

        @test desc_default isa String
        @test desc_python isa String
        @test desc_concise isa String
        @test !isempty(desc_default)

        # Different styles should produce different output
        # (or same if CONCISE is default)
        @test occursin("style_test", desc_default)
        @test occursin("style_test", desc_python)
    end

    @testset "get_tool_schema" begin
        @tool TestSchemaTool "schema_test" "Test schema" [
            (:required_param, "string", "A required param", true, nothing),
            (:optional_param, "integer", "An optional param", false, 42),
            (:flag, "boolean", "A boolean flag", false, nothing),
        ]

        schema = get_tool_schema(TestSchemaTool)
        @test schema.name == "schema_test"
        @test schema.description == "Test schema"
        @test length(schema.params) == 3

        @test schema.params[1].name == "required_param"
        @test schema.params[1].type == "string"
        @test schema.params[1].required == true

        @test schema.params[2].name == "optional_param"
        @test schema.params[2].required == false

        @test schema.params[3].type == "boolean"
    end

    @testset "Reserved field name validation" begin
        # Test that reserved names are rejected with helpful error messages
        for reserved_name in [:id, :result, :auto_run]
            @test_throws LoadError @eval @tool ReservedTest "test" "Test" [
                ($(QuoteNode(reserved_name)), "string", "Should fail", true, nothing),
            ]
        end

        # Verify 'content' is NOT reserved (can be used as param name)
        @tool ContentParamTool "content_test" "Test content param" [
            (:content, "codeblock", "Content is allowed as param", true, nothing),
        ]
        @test toolname(ContentParamTool) == "content_test"
    end

end
