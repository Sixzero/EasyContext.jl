# test_tool_macro_real_tools.jl
# Test @tool macro with real tool definitions similar to existing tools

using Test
using EasyContext: AbstractTool, @tool
using EasyContext: get_description, toolname, get_tool_schema, execute, result2string
using EasyContext: execute_required_tools, is_cancelled, create_tool
using ToolCallFormat: CONCISE, PYTHON, MINIMAL, TYPESCRIPT
using ToolCallFormat: ParsedCall, ParsedValue
using UUIDs: UUID, uuid4

println("=" ^ 60)
println("Testing @tool macro with real tool definitions")
println("=" ^ 60)

#==============================================================================#
# Define tools using @tool macro
#==============================================================================#

# 1. Simple single-param tool (like SendKeyTool)
@tool SendKeyToolNew "send_key" "Send keyboard input" [
    (:text, "string", "Text to send", true, nothing),
] (tool; kwargs...) -> begin
    tool.result = "Sending keys: $(tool.text)"
end

# 2. Two-param tool (like ClickTool)
@tool ClickToolNew "click" "Click on screen coordinates" [
    (:x, "integer", "X coordinate", true, nothing),
    (:y, "integer", "Y coordinate", true, nothing),
] (tool; kwargs...) -> begin
    tool.result = "Clicking at coordinates ($(tool.x), $(tool.y))"
end

# 3. Tool with optional param (like CatFileTool simplified)
@tool CatFileToolNew "cat_file" "Read file content" [
    (:file_path, "string", "Path to file", true, nothing),
    (:line_start, "integer", "Start line (optional)", false, nothing),
    (:line_end, "integer", "End line (optional)", false, nothing),
] (tool; kwargs...) -> begin
    # Simplified - just return file path for testing
    range_str = if tool.line_start !== nothing
        tool.line_end !== nothing ? ":$(tool.line_start)-$(tool.line_end)" : ":$(tool.line_start)-"
    else
        ""
    end
    tool.result = "Reading file: $(tool.file_path)$(range_str)"
end

# 4. Tool with codeblock (like CreateFileTool)
# Now we can use 'content' as param name since it's not in base fields
@tool CreateFileToolNew "create_file" "Create a new file with content" [
    (:file_path, "string", "Path for the new file", true, nothing),
    (:content, "codeblock", "File content", true, nothing),
] (tool; kwargs...) -> begin
    tool.result = "Creating file: $(tool.file_path) with $(length(tool.content)) chars"
end

# 5. Tool with codeblock (like ShellBlockTool/Bash)
@tool BashToolNew "bash" "Execute shell commands" [
    (:command, "codeblock", "Shell commands to execute", true, nothing),
] (tool; kwargs...) -> begin
    tool.result = "Would execute: $(tool.command)"
end

# 6. Search tool (like WebSearchTool)
@tool WebSearchToolNew "web_search" "Search the web for information" [
    (:query, "string", "Search query", true, nothing),
] (tool; kwargs...) -> begin
    tool.result = "Searching for: $(tool.query)"
end

# 7. Tool with custom result formatting (like WorkspaceSearchTool)
@tool WorkspaceSearchToolNew "workspace_search" "Semantic search in workspace" [
    (:query, "string", "Search query", true, nothing),
] (
    (tool; kwargs...) -> begin
        tool.result = "Found 3 results for: $(tool.query)"
    end
) (
    (tool) -> """
Search results for: $(tool.query)

$(tool.result)"""
)

# 8. Passive tool (like ReasonTool - no params, no execute)
# Uses @tool with empty params or no params
@tool ReasonToolNew "ReasonTool" "Store reasoning"
@tool ThinkingToolNew "ThinkingTool" "Store thinking" []

#==============================================================================#
# Tests
#==============================================================================#

@testset "Real Tool Definitions with @tool" begin

    @testset "SendKeyToolNew" begin
        @test toolname(SendKeyToolNew) == "send_key"

        tool = SendKeyToolNew(text="Hello World")
        @test tool.text == "Hello World"

        execute(tool)
        @test tool.result == "Sending keys: Hello World"
        @test result2string(tool) == "Sending keys: Hello World"

        # Test schema
        schema = get_tool_schema(SendKeyToolNew)
        @test schema.name == "send_key"
        @test length(schema.params) == 1
        @test schema.params[1].name == "text"
        @test schema.params[1].type == "string"
        @test schema.params[1].required == true

        println("\n--- SendKeyToolNew description ---")
        println(get_description(SendKeyToolNew))
    end

    @testset "ClickToolNew" begin
        @test toolname(ClickToolNew) == "click"

        tool = ClickToolNew(x=100, y=200)
        @test tool.x == 100
        @test tool.y == 200

        execute(tool)
        @test tool.result == "Clicking at coordinates (100, 200)"

        schema = get_tool_schema(ClickToolNew)
        @test length(schema.params) == 2
        @test schema.params[1].type == "integer"

        println("\n--- ClickToolNew description ---")
        println(get_description(ClickToolNew))
    end

    @testset "CatFileToolNew" begin
        @test toolname(CatFileToolNew) == "cat_file"

        # Without line range
        tool1 = CatFileToolNew(file_path="/tmp/test.txt")
        execute(tool1)
        @test tool1.result == "Reading file: /tmp/test.txt"

        # With line range
        tool2 = CatFileToolNew(file_path="/tmp/test.txt", line_start=10, line_end=20)
        execute(tool2)
        @test tool2.result == "Reading file: /tmp/test.txt:10-20"

        # With just start line
        tool3 = CatFileToolNew(file_path="/tmp/test.txt", line_start=5)
        execute(tool3)
        @test tool3.result == "Reading file: /tmp/test.txt:5-"

        println("\n--- CatFileToolNew description ---")
        println(get_description(CatFileToolNew))
    end

    @testset "CreateFileToolNew" begin
        @test toolname(CreateFileToolNew) == "create_file"

        tool = CreateFileToolNew(file_path="/tmp/new.txt", content="Hello\nWorld")
        execute(tool)
        @test tool.result == "Creating file: /tmp/new.txt with 11 chars"

        schema = get_tool_schema(CreateFileToolNew)
        @test schema.params[2].type == "codeblock"

        println("\n--- CreateFileToolNew description ---")
        println(get_description(CreateFileToolNew))
    end

    @testset "BashToolNew" begin
        @test toolname(BashToolNew) == "bash"

        tool = BashToolNew(command="ls -la")
        execute(tool)
        @test tool.result == "Would execute: ls -la"

        schema = get_tool_schema(BashToolNew)
        @test schema.params[1].type == "codeblock"

        println("\n--- BashToolNew description ---")
        println(get_description(BashToolNew))
    end

    @testset "WebSearchToolNew" begin
        @test toolname(WebSearchToolNew) == "web_search"
        @test execute_required_tools(WebSearchToolNew()) == false  # auto_run defaults to false

        tool = WebSearchToolNew(query="julia programming")
        execute(tool)
        @test tool.result == "Searching for: julia programming"

        println("\n--- WebSearchToolNew description ---")
        println(get_description(WebSearchToolNew))
    end

    @testset "WorkspaceSearchToolNew with custom result" begin
        @test toolname(WorkspaceSearchToolNew) == "workspace_search"

        tool = WorkspaceSearchToolNew(query="function definition")
        execute(tool)

        result_str = result2string(tool)
        @test occursin("Search results for: function definition", result_str)
        @test occursin("Found 3 results", result_str)

        println("\n--- WorkspaceSearchToolNew description ---")
        println(get_description(WorkspaceSearchToolNew))
        println("\n--- Result formatting ---")
        println(result_str)
    end

    @testset "Passive tools" begin
        @test toolname(ReasonToolNew) == "ReasonTool"
        @test toolname(ThinkingToolNew) == "ThinkingTool"

        tool = ReasonToolNew()
        @test tool.id isa UUID
        @test tool.content == ""
        @test execute_required_tools(tool) == false
    end

    @testset "CallStyle variations" begin
        println("\n" * "=" ^ 60)
        println("CallStyle variations for BashToolNew")
        println("=" ^ 60)

        println("\n--- CONCISE style ---")
        println(get_description(BashToolNew, CONCISE))

        println("\n--- PYTHON style ---")
        println(get_description(BashToolNew, PYTHON))

        println("\n--- MINIMAL style ---")
        println(get_description(BashToolNew, MINIMAL))

        println("\n--- TYPESCRIPT style ---")
        println(get_description(BashToolNew, TYPESCRIPT))

        # Just verify they don't error
        @test !isempty(get_description(BashToolNew, CONCISE))
        @test !isempty(get_description(BashToolNew, PYTHON))
        @test !isempty(get_description(BashToolNew, MINIMAL))
        @test !isempty(get_description(BashToolNew, TYPESCRIPT))
    end

    @testset "Tool interface compliance" begin
        # All tools should satisfy the AbstractTool interface
        for T in [SendKeyToolNew, ClickToolNew, CatFileToolNew, CreateFileToolNew,
                  BashToolNew, WebSearchToolNew, WorkspaceSearchToolNew]
            @test T <: AbstractTool
            @test !isempty(toolname(T))
            @test !isempty(get_description(T))
            @test get_tool_schema(T) !== nothing
        end

        # Passive tools
        for T in [ReasonToolNew, ThinkingToolNew]
            @test T <: AbstractTool
            @test !isempty(toolname(T))
        end
    end

    @testset "create_tool from ParsedCall" begin
        println("\n" * "=" ^ 60)
        println("Testing create_tool from ParsedCall")
        println("=" ^ 60)

        # Simple string param from kwargs
        call1 = ParsedCall(name="send_key", kwargs=Dict("text" => ParsedValue("Hello from ParsedCall")))
        tool1 = create_tool(SendKeyToolNew, call1)
        @test tool1.text == "Hello from ParsedCall"
        println("✓ SendKeyToolNew from ParsedCall: text=$(tool1.text)")

        # Integer params
        call2 = ParsedCall(name="click", kwargs=Dict(
            "x" => ParsedValue(150),
            "y" => ParsedValue(250)
        ))
        tool2 = create_tool(ClickToolNew, call2)
        @test tool2.x == 150
        @test tool2.y == 250
        println("✓ ClickToolNew from ParsedCall: x=$(tool2.x), y=$(tool2.y)")

        # Codeblock from call.content
        call3 = ParsedCall(name="bash", content="echo 'from content'")
        tool3 = create_tool(BashToolNew, call3)
        @test tool3.command == "echo 'from content'"
        println("✓ BashToolNew from ParsedCall (content): command=$(repr(tool3.command))")

        # Codeblock from kwargs
        call4 = ParsedCall(name="bash", kwargs=Dict("command" => ParsedValue("echo 'from kwargs'")))
        tool4 = create_tool(BashToolNew, call4)
        @test tool4.command == "echo 'from kwargs'"
        println("✓ BashToolNew from ParsedCall (kwargs): command=$(repr(tool4.command))")

        # Mixed params
        call5 = ParsedCall(name="cat_file", kwargs=Dict(
            "file_path" => ParsedValue("/tmp/test.txt"),
            "line_start" => ParsedValue(10),
            "line_end" => ParsedValue(20)
        ))
        tool5 = create_tool(CatFileToolNew, call5)
        @test tool5.file_path == "/tmp/test.txt"
        @test tool5.line_start == 10
        @test tool5.line_end == 20
        println("✓ CatFileToolNew from ParsedCall: path=$(tool5.file_path), lines=$(tool5.line_start)-$(tool5.line_end)")

        # Passive tool
        call6 = ParsedCall(name="ReasonTool", content="reasoning content")
        tool6 = create_tool(ReasonToolNew, call6)
        @test tool6.content == "reasoning content"
        println("✓ ReasonToolNew from ParsedCall: content=$(repr(tool6.content))")
    end

    @testset "create_tool round-trip (create + execute)" begin
        println("\n" * "=" ^ 60)
        println("Testing create_tool + execute round-trip")
        println("=" ^ 60)

        # Create from ParsedCall and execute - WebSearchToolNew
        call1 = ParsedCall(name="web_search", kwargs=Dict("query" => ParsedValue("test query")))
        tool = create_tool(WebSearchToolNew, call1)
        execute(tool)
        @test tool.result == "Searching for: test query"
        println("✓ WebSearchToolNew round-trip: $(tool.result)")

        # Create from ParsedCall and execute - ClickToolNew
        call2 = ParsedCall(name="click", kwargs=Dict(
            "x" => ParsedValue(100),
            "y" => ParsedValue(200)
        ))
        tool2 = create_tool(ClickToolNew, call2)
        execute(tool2)
        @test tool2.result == "Clicking at coordinates (100, 200)"
        println("✓ ClickToolNew round-trip: $(tool2.result)")
    end

end

println("\n" * "=" ^ 60)
println("All tests completed!")
println("=" ^ 60)
