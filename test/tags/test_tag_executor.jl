using Test
using EasyContext: Tag, execute_tag, tag2cmd, tag2codeblock, CodeBlock

@testset "Tag Executor Tests" begin
    @testset "tag2codeblock Generation" begin
        # Test MODIFY tag with language
        modify_tag = Tag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="```julia\ntest content\n```"
        )
        cb = tag2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"
        @test cb.language == "julia"

        # Test CREATE tag with language
        create_tag = Tag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="```python\nnew content\n```"
        )
        cb = tag2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"
        @test cb.language == "python"

        # Test shell command tag without explicit language
        shell_tag = Tag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="```\necho 'test'\n```"
        )
        cb = tag2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
        @test cb.language == "sh"  # defaults to sh

        # Test MODIFY tag
        modify_tag = Tag(
            name="MODIFY",
            args=["test.txt"],
            kwargs=Dict{String,String}(),
            content="test content"
        )
        cb = tag2codeblock(modify_tag)
        @test cb isa CodeBlock
        @test cb.type == :MODIFY
        @test cb.file_path == "test.txt"
        @test cb.content == "test content"

        # Test CREATE tag
        create_tag = Tag(
            name="CREATE",
            args=["new.txt"],
            kwargs=Dict{String,String}(),
            content="new content"
        )
        cb = tag2codeblock(create_tag)
        @test cb isa CodeBlock
        @test cb.type == :CREATE
        @test cb.file_path == "new.txt"
        @test cb.content == "new content"

        # Test shell command tag
        shell_tag = Tag(
            name="SHELL",
            args=String[],
            kwargs=Dict{String,String}(),
            content="echo 'test'"
        )
        cb = tag2codeblock(shell_tag)
        @test cb isa CodeBlock
        @test cb.type == :SHELL
        @test cb.content == "echo 'test'"
    end

    @testset "Execute Tag with Mocks" begin
        mktempdir() do dir
            # Test CREATE
            create_tag = Tag(
                name="CREATE",
                args=[joinpath(dir, "test.txt")],
                kwargs=Dict{String,String}(),
                content="test content"
            )
            result = execute_tag(create_tag; no_confirm=true)
            @test isfile(joinpath(dir, "test.txt"))
            @test read(joinpath(dir, "test.txt"), String) == "test content\n"

            # Test MODIFY
            modify_tag = Tag(
                name="MODIFY",
                args=[joinpath(dir, "test.txt")],
                kwargs=Dict{String,String}(),
                content="modified content"
            )
            result = execute_tag(modify_tag; no_confirm=true)
            @test !isempty(result)
        end
    end
end
