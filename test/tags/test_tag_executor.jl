using Test
using EasyContext: ToolTag, execute, tag2cmd, tool2codeblock, CodeBlock

@testset "ToolTag Executor Tests" begin
    @testset "tool2codeblock Generation" begin
        # Test MODIFY tag with language
        modify_tag = ToolTag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="```julia\ntest content\n```"
        )
        cb = tool2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"
        @test cb.language == "julia"

        # Test CREATE tag with language
        create_tag = ToolTag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="```python\nnew content\n```"
        )
        cb = tool2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"
        @test cb.language == "python"

        # Test shell tool tag without explicit language
        shell_tag = ToolTag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="```\necho 'test'\n```"
        )
        cb = tool2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
        @test cb.language == "sh"  # defaults to sh

        # Test MODIFY tag
        modify_tag = ToolTag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="test content"
        )
        cb = tool2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"

        # Test CREATE tag
        create_tag = ToolTag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="new content"
        )
        cb = tool2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"

        # Test shell tool tag
        shell_tag = ToolTag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="echo 'test'"
        )
        cb = tool2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
    end

    @testset "Execute ToolTag with Mocks" begin
        mktempdir() do dir
            # Test CREATE
            create_tag = ToolTag(
                name="CREATE",
                args=[joinpath(dir, "test.txt")],
                kwargs=Dict{String,String}(),
                content="test content"
            )
            result = execute(create_tag; no_confirm=true)
            @test isfile(joinpath(dir, "test.txt"))
            @test read(joinpath(dir, "test.txt"), String) == "test content\n"

            # Test MODIFY
            modify_tag = ToolTag(
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
