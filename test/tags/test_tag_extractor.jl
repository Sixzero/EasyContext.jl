using Test
using EasyContext
using UUIDs  # Add UUIDs import for uuid4()
using EasyContext: StreamParser, ToolTag, extract_tool_calls, reset!, serialize
using EasyContext: shell_ctx_2_string, SHELL_BLOCK_TAG

@testset failfast=true "StreamParser Tests" begin
    @testset "Constructor" begin
        parser = StreamParser()
        @test parser.last_processed_index[] == 0
        @test isempty(parser.tool_tasks)
        @test isempty(parser.tool_results)
        @test parser.full_content == ""
        @test !parser.skip_execution
        @test !parser.no_confirm
    end

    @testset "extract_tool_calls" begin
        parser = StreamParser()
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

        result = extract_tool_calls(content, parser; root_path="")

        @test length(parser.tool_tasks) == 2
    end

    @testset "reset!" begin
        parser = StreamParser()
        parser.last_processed_index[] = 100
        test_id = uuid4()  # Create a proper UUID
        parser.tool_tasks[test_id] = @task nothing
        parser.tool_results[test_id] = "test result"
        parser.full_content = "Some content"

        reset!(parser)

        @test parser.last_processed_index[] == 0
        @test isempty(parser.tool_tasks)
        @test isempty(parser.tool_results)
        @test parser.full_content == ""
    end

    @testset "Nested tags" begin
        parser = StreamParser()
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
        parser = StreamParser()

        # Test unclosed CREATE tag
        content = """
        Some text before
        CREATE new_file.txt
        ```julia
        code content
        ```
        Some text after
        """
        extract_tool_calls(content, parser)
        @test isempty(parser.tool_tasks) # Should not create command without closing tag

        # Test unclosed MODIFY tag
        content = """
        Some text before
        CREATE testfile2.txt
        ```julia
        code content
        ```
        Some text after
        """
        reset!(parser)
        extract_tool_calls(content, parser)
        @test isempty(parser.tool_tasks) # Should not create command without closing tag

        # Test unclosed code block
        content = """
        Some text before
        CREATE new_file.txt
        ```julia
        code content
        ```
        Some text after
        """
        reset!(parser)
        extract_tool_calls(content, parser)
        @test isempty(parser.tool_tasks) # Should not create command with unclosed code block
    end

    @testset "Partial streaming extraction" begin
        parser = StreamParser()

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

        extract_tool_calls(content1, parser)
        @test isempty(parser.tool_tasks) # Should not create command from partial content

        extract_tool_calls(content2, parser)
        extract_tool_calls("\n", parser, is_flush=true)
        @show parser
        @test length(parser.tool_tasks) == 1 # Should create command when complete
    end

    @testset "Raw ToolTag parsing" begin
        parser = StreamParser()
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

        extract_tool_calls(content, parser; root_path="/test/root")
        
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
        parser = StreamParser()
        content = """
        Some text
        CLICK 100 200
        SENDKEY ctrl+c
        CATFILE /tmp/test.txt
        More text
        """

        extract_tool_calls(content, parser; root_path="/test/root")
        
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
        parser = StreamParser()
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

        extract_tool_calls(content, parser; root_path="/tmp", is_flush=true)
        
        for t in parser.tool_tags
            display(t.content)
        end
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
end
;