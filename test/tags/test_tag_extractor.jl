using Test
using EasyContext
using UUIDs  # Add UUIDs import for uuid4()
using EasyContext: StreamParser, CommandTag, extract_commands, reset!, serialize

@testset failfast=true "StreamParser Tests" begin
    @testset "Constructor" begin
        parser = StreamParser()
        @test parser.last_processed_index[] == 0
        @test isempty(parser.command_tasks)
        @test isempty(parser.command_results)
        @test parser.full_content == ""
        @test !parser.skip_execution
        @test !parser.no_confirm
    end

    @testset "extract_commands" begin
        parser = StreamParser()
        content = """
        Some text before
        <MODIFY path/to/file force=true>
        ```julia
        This is a modification
        ```
        </MODIFY>
        Some text between
        <CREATE new_file.txt>
        ```
        New file content
        ```
        </CREATE>
        Some text after
        """

        result = extract_commands(content, parser; root_path="")

        @test length(parser.command_tasks) == 2
    end

    @testset "reset!" begin
        parser = StreamParser()
        parser.last_processed_index[] = 100
        test_id = uuid4()  # Create a proper UUID
        parser.command_tasks[test_id] = @task nothing
        parser.command_results[test_id] = "test result"
        parser.full_content = "Some content"

        reset!(parser)

        @test parser.last_processed_index[] == 0
        @test isempty(parser.command_tasks)
        @test isempty(parser.command_results)
        @test parser.full_content == ""
    end

    @testset "to_string CommandTag Results Formatting" begin
        parser = StreamParser()
        cmd1 = CommandTag("SHELL", "command1", Dict{String,String}("result" => "output1"))  # Fixed constructor args
        cmd2 = CommandTag("TEST", "command2", Dict{String,String}("result" => "output2"))   # Fixed constructor args
        parser.command_results[cmd1.id] = "output1"
        parser.command_results[cmd2.id] = "output2"

        result = shell_ctx_2_string(parser)

        @test occursin("```sh", result)
        @test occursin("```sh_run_result", result)
        @test occursin("output1", result)
        @test occursin("output2", result)
    end

    @testset "Nested tags" begin
        parser = StreamParser()
        content = """
        OUTER arg1
        First line
        INNER arg2
        Nested content
        /INNER
        Last line
        /OUTER
        """

        @test_throws ErrorException extract_commands(content, parser)
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
        extract_commands(content, parser)
        @test isempty(parser.command_tasks) # Should not create command without closing tag

        # Test unclosed MODIFY tag
        content = """
        Some text before
        MODIFY path/to/file
        ```julia
        code content
        ```
        Some text after
        """
        reset!(parser)
        extract_commands(content, parser)
        @test isempty(parser.command_tasks) # Should not create command without closing tag

        # Test unclosed code block
        content = """
        Some text before
        CREATE new_file.txt
        ```julia
        code content
        /CREATE
        Some text after
        """
        reset!(parser)
        extract_commands(content, parser)
        @test isempty(parser.command_tasks) # Should not create command with unclosed code block
    end

    @testset "Partial streaming extraction" begin
        parser = StreamParser()

        # Test streaming content in chunks
        content1 = """
        Some text before
        MODIFY path/to/file
        ```julia
        """
        content2 = """
        code content
        ```
        /MODIFY
        """

        extract_commands(content1, parser)
        @test isempty(parser.command_tasks) # Should not create command from partial content

        extract_commands(content2, parser)
        @test length(parser.command_tasks) == 1 # Should create command when complete
    end
end
;