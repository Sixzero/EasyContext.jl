using Test
using EasyContext
using UUIDs  # Add UUIDs import for uuid4()
using EasyContext: ToolTagExtractor, ToolTag, extract_tool_calls, serialize
using EasyContext: SHELL_BLOCK_TAG, AbstractTool, are_tools_cancelled

@testset failfast=true "ToolTagExtractor Tests" begin
    @testset "Constructor" begin
        parser = ToolTagExtractor([ShellBlockTool, CreateFileTool])
        @test parser.last_processed_index[] == 0
        @test isempty(parser.tool_tasks)
        @test parser.full_content == ""
        @test !parser.skip_execution
        @test !parser.no_confirm
    end

    @testset "extract_tool_calls" begin
        parser = ToolTagExtractor([ShellBlockTool, CreateFileTool])
        content = """
        Some text before
        $SHELL_BLOCK_TAG
        ```julia
        echo ALL OK
        This is a modification
        ```endblock
        Some text between
        CREATE new_file.txt
        ```
        New file content
        ```endblock
        Some text after
        """

        result = extract_tool_calls(content, parser, stdout; kwargs=Dict("root_path" => ""))

        @test length(parser.tool_tags) == 2
    end


    @testset "Nested tags" begin
        parser = ToolTagExtractor([ShellBlockTool, CatFileTool])
        content = """
        SHELL_BLOCK_TAG arg1
        ```
        First line
        CATFILE arg2
        Last line
        ```
        Other things.
        """

        # @test_throws ErrorException extract_tool_calls(content, parser)
    end

    @testset "Unclosed tags handling" begin
        parser = ToolTagExtractor([ShellBlockTool, CatFileTool, CreateFileTool])

        # Test unclosed CREATE tag
        content = """
        Some text before
        CREATE new_file.txt
        ```julia
        code content
        ```
        Some text after
        """
        extract_tool_calls(content, parser, stdout)
        @test isempty(parser.tool_tasks) # Should not create command without closing tag

    end

    @testset "Partial streaming extraction" begin
        parser = ToolTagExtractor([ShellBlockTool, CatFileTool, CreateFileTool])

        # Test streaming content in chunks
        content1 = """
        Some text before
        CREATE testfile3.txt
        ```julia
        """
        content2 = """
        code content
        ```
        """

        extract_tool_calls(content1, parser, stdout)
        @test isempty(parser.tool_tasks) # Should not create command from partial content

        extract_tool_calls(content2, parser, stdout)
        extract_tool_calls("\n", parser, stdout, is_flush=true)
        @test length(parser.tool_tasks) == 1 # Should create command when complete
    end

    @testset "Raw ToolTag parsing" begin
        parser = ToolTagExtractor([ShellBlockTool, CatFileTool, CreateFileTool])
        content = """
        Some text before
        $SHELL_BLOCK_TAG path/to/file
        ```julia
        echo ALL OK
        This is a modification
        ```
        Some text between
        CREATE new_file.txt
        ```
        New file content
        ```endblock
        Some text after
        """

        extract_tool_calls(content, parser, stdout; kwargs=Dict("root_path" => "/test/root"))
        
        @test length(parser.tool_tags) == 2
        
        # Test first tool tag (SHELL_BLOCK)
        shell_tag = parser.tool_tags[1]
        @test shell_tag.name == SHELL_BLOCK_TAG
        @test shell_tag.args == "path/to/file"
        @test shell_tag.content == "```julia\necho ALL OK\nThis is a modification\n```"
        @test shell_tag.kwargs["root_path"] == "/test/root"

        # Test second tool tag (CREATE)
        create_tag = parser.tool_tags[2]
        @test create_tag.name == "CREATE"
        @test create_tag.args == "new_file.txt"
        @test create_tag.content == "```\nNew file content\n```endblock"
        @test create_tag.kwargs["root_path"] == "/test/root"
    end

    @testset "ToolTag with immediate commands" begin
        parser = ToolTagExtractor([ClickTool, SendKeyTool, CatFileTool])
        content = """
        Some text
        CLICK 100 200
        SENDKEY ctrl+c
        CATFILE /tmp/test.txt
        More text
        """

        extract_tool_calls(content, parser, stdout; kwargs=Dict("root_path" => "/test/root"))
        
        @test length(parser.tool_tags) == 3
        
        click_tag = parser.tool_tags[1]
        @test click_tag.name == "CLICK"
        @test click_tag.args == "100 200"
        @test isempty(click_tag.content)

        sendkey_tag = parser.tool_tags[2]
        @test sendkey_tag.name == "SENDKEY"
        @test sendkey_tag.args == "ctrl+c"
        @test isempty(sendkey_tag.content)

        catfile_tag = parser.tool_tags[3]
        @test catfile_tag.name == "CATFILE"
        @test catfile_tag.args == "/tmp/test.txt"
        @test isempty(catfile_tag.content)
    end
    @testset "Docstring in content handling" begin
        parser = ToolTagExtractor([ShellBlockTool, CreateFileTool])
        content = """
        \"\"\"
        Some docstring
        ```
        with an example
        ```
        \"\"\"
        Some text before
        $SHELL_BLOCK_TAG path/to/file
        ```julia
        echo ALL OK
        This is a modification
        ```
        jsust a multiline assignment = \"\"\"
        yeah we know
        \"\"\"
        Some text between
        CREATE new_file.txt
        ```
        New file content
        another_multiline_assignment = \"\"\"
        yeah we know it again
        \"\"\"
        yes
        ```
        No need for endblock.
        Some text after
        """

        extract_tool_calls(content, parser, stdout; kwargs=Dict("root_path" => "/tmp"), is_flush=true)
        
        @test length(parser.tool_tags) == 2
        
        # Test that docstring code blocks didn't interfere
        shell_tag = parser.tool_tags[1]
        @test shell_tag.name == SHELL_BLOCK_TAG
        @test shell_tag.args == "path/to/file"
        @test shell_tag.content == "```julia\necho ALL OK\nThis is a modification\n```"
        @test !occursin("yeah we know", shell_tag.content) # Verify multiline assignment wasn't captured

        create_tag = parser.tool_tags[2]
        @test create_tag.name == "CREATE"
        @test create_tag.args == "new_file.txt"
        @test create_tag.content == "```\nNew file content\nanother_multiline_assignment = \"\"\"\nyeah we know it again\n\"\"\"\nyes\n```"
        @test occursin("yeah we know it again", create_tag.content) # This multiline assignment should be part of content
    end
    @testset "ToolTag with $STOP_SEQUENCE instant execution" begin
        parser = ToolTagExtractor([ClickTool, SendKeyTool, CatFileTool])
        content = """
        Some text
        CLICK 100 200
        SENDKEY ctrl+c
        CATFILE /tmp/test.txt $STOP_SEQUENCE
        More text
        """

        extract_tool_calls(content, parser, stdout; kwargs=Dict("root_path" => "/test/root"))
        
        @test length(parser.tool_tags) == 3
        
        click_tag = parser.tool_tags[1]
        @test click_tag.name == "CLICK"
        @test click_tag.args == "100 200"
        @test isempty(click_tag.content)

        sendkey_tag = parser.tool_tags[2]
        @test sendkey_tag.name == "SENDKEY"
        @test sendkey_tag.args == "ctrl+c"
        @test isempty(sendkey_tag.content)

        catfile_tag = parser.tool_tags[3]
        @test catfile_tag.name == "CATFILE"
        @test catfile_tag.args == "/tmp/test.txt"
        @test isempty(catfile_tag.content)
    end

    @testset "ToolTag argument parsing" begin
        parser = ToolTagExtractor([ShellBlockTool, CatFileTool, JuliaSearchTool])
        
        # Test single quoted argument
        content = """
        CATFILE "path/to/my file.txt"
        """
        extract_tool_calls(content, parser)
        @test parser.tool_tags[1].args == "path/to/my file.txt"
        empty!(parser.tool_tags)
        
        # Test multiple quoted arguments
        content = """
        JULIA_SEARCH "first query" "second query"
        """
        extract_tool_calls(content, parser)
        @test parser.tool_tags[1].args == "\"first query\" \"second query\""
        empty!(parser.tool_tags)
        
        # Test mixed quoted and unquoted
        content = """
        JULIA_SEARCH "quoted arg" unquoted_arg
        """
        extract_tool_calls(content, parser)
        @test parser.tool_tags[1].args == "\"quoted arg\" unquoted_arg"
    end
    @testset "Tool cancellation detection" begin
        parser = ToolTagExtractor([ShellBlockTool])
    
        content = """
        SHELL_BLOCK
        ```sh
        echo "First command"
        ```endblock
        
        SHELL_BLOCK
        ```sh
        echo "Second command"
        ```endblock
        """
        
        # Simulate execution where second command is cancelled
        extract_tool_calls(content, parser, stdout, kwargs=Dict("root_path" => "."))
        
        # Execute first command normally
        first_tool = fetch(first(values(parser.tool_tasks)))
        execute(first_tool; no_confirm=true)
        
        # Simulate cancellation for second command
        second_tool = fetch(last(values(parser.tool_tasks)))
        push!(second_tool.run_results, EXECUTION_CANCELLED)
    
        # Check if any tool was cancelled
        @test are_tools_cancelled(parser) == true
    
        # Clear for next test
        empty!(parser.tool_tasks)
        empty!(parser.tool_tags)
        
        # Test when no cancellation happens
        extract_tool_calls(content, parser, stdout, kwargs=Dict("root_path" => "."))
        execute_tools(parser; no_confirm=true)
        @test are_tools_cancelled(parser) == false
    end
end
;
