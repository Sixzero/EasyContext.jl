using Test
using EasyContext: CommandTag, execute, tag2cmd, command2codeblock, CodeBlock

@testset "CommandTag Executor Tests" begin
    @testset "command2codeblock Generation" begin
        # Test MODIFY tag with language
        modify_tag = CommandTag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="```julia\ntest content\n```"
        )
        cb = command2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"
        @test cb.language == "julia"

        # Test CREATE tag with language
        create_tag = CommandTag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="```python\nnew content\n```"
        )
        cb = command2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"
        @test cb.language == "python"

        # Test shell command tag without explicit language
        shell_tag = CommandTag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="```\necho 'test'\n```"
        )
        cb = command2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
        @test cb.language == "sh"  # defaults to sh

        # Test MODIFY tag
        modify_tag = CommandTag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="test content"
        )
        cb = command2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"

        # Test CREATE tag
        create_tag = CommandTag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="new content"
        )
        cb = command2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"

        # Test shell command tag
        shell_tag = CommandTag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="echo 'test'"
        )
        cb = command2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
    end

    @testset "Execute CommandTag with Mocks" begin
        mktempdir() do dir
            # Test CREATE
            create_tag = CommandTag(
                name="CREATE",
                args=[joinpath(dir, "test.txt")],
                kwargs=Dict{String,String}(),
                content="test content"
            )
            result = execute(create_tag; no_confirm=true)
            @test isfile(joinpath(dir, "test.txt"))
            @test read(joinpath(dir, "test.txt"), String) == "test content\n"

            # Test MODIFY
            modify_tag = CommandTag(
                name="MODIFY",
                args=[joinpath(dir, "test.txt")],
                kwargs=Dict{String,String}(),
                content="modified content"
            )
            result = execute(modify_tag; no_confirm=true)
            @test !isempty(result)
        end
    end
end
