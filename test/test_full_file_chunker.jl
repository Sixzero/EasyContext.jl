using Test
using EasyContext
using EasyContext: FullFileChunker, NewlineChunker, FileChunk, get_content, get_source
using EasyContext: CharCount
using RAGTools

@testset "FullFileChunker Tests" begin
    @testset "Constructor" begin
        chunker = FullFileChunker()
        @test chunker.chunker isa NewlineChunker{FileChunk}

        # Keywords are forwarded to the inner NewlineChunker
        custom = FullFileChunker(max_tokens=5000, estimation_method=CharCount)
        @test custom.chunker.max_tokens == 5000
        @test custom.chunker.estimation_method == CharCount

        # Passing an explicit inner chunker still works
        inner = NewlineChunker{FileChunk}(max_tokens=1234)
        @test FullFileChunker(chunker=inner).chunker.max_tokens == 1234

        # Mixing an explicit chunker with forwarded keywords is rejected
        @test_throws ArgumentError FullFileChunker(chunker=inner, max_tokens=10)
    end

    @testset "get_chunks splits large files by tokens" begin
        mktempdir() do dir
            file = joinpath(dir, "test.txt")
            write(file, join(["Line $i " * "x"^200 for i in 1:100], "\n"))

            chunker = FullFileChunker(max_tokens=200)
            chunks = RAGTools.get_chunks(chunker, [file])

            @test all(c -> c isa FileChunk, chunks)
            @test length(chunks) > 1                                # split into multiple chunks
            @test all(c -> occursin("test.txt", get_source(c)), chunks)
            @test all(c -> occursin("Line", get_content(c)), chunks)

            # Rendering contract: "# source\ncontent"
            @test string(chunks[1]) == "# $(get_source(chunks[1]))\n$(get_content(chunks[1]))"
            @test occursin(":1-", get_source(chunks[1]))            # split chunks carry a line range

            # Line ranges are continuous and fully cover the 100-line file
            ranges = [(c.source.from_line, c.source.to_line) for c in chunks]
            @test all(r -> !isnothing(r[1]) && !isnothing(r[2]) && r[1] <= r[2], ranges)
            @test ranges[1][1] == 1
            @test ranges[end][2] == 100
            for i in 2:length(ranges)
                @test ranges[i][1] == ranges[i-1][2] + 1
            end
        end
    end

    @testset "small file is a single chunk without line numbers" begin
        mktempdir() do dir
            file = joinpath(dir, "small.txt")
            write(file, "This is a small file that doesn't need to be split.")

            chunks = RAGTools.get_chunks(FullFileChunker(max_tokens=1000), [file])
            @test length(chunks) == 1
            @test isnothing(chunks[1].source.from_line)
            @test occursin("small file", get_content(chunks[1]))
        end
    end

    @testset "empty files don't break the chain" begin
        mktempdir() do dir
            empty_file = joinpath(dir, "empty.txt"); touch(empty_file)
            non_empty = joinpath(dir, "nonempty.txt"); write(non_empty, "content")

            chunks = RAGTools.get_chunks(FullFileChunker(), [empty_file, non_empty])
            @test length(chunks) == 2
            @test occursin("content", get_content(chunks[2]))
        end
    end
end
