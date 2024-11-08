using Test
using EasyContext
using EasyContext: FullFileChunker, RAGTools
using EasyContext: GPT2Approximation, CharCount, get_chunk_standard_format
using Random

const RAG = RAGTools

@testset "FullFileChunker Tests" begin
    @testset "Constructor" begin
        chunker = FullFileChunker()
        @test chunker.max_tokens == 8000
        @test chunker.estimation_method == GPT2Approximation
        @test chunker.line_number_token_estimate == 10

        custom_chunker = FullFileChunker(max_tokens=5000, estimation_method=CharCount, line_number_token_estimate=15)
        @test custom_chunker.max_tokens == 5000
        @test custom_chunker.estimation_method == CharCount
        @test custom_chunker.line_number_token_estimate == 15
    end

    @testset "get_chunks functionality" begin
        mktempdir() do temp_dir
            test_file = joinpath(temp_dir, "test.txt")
            test_content = join(["Line $i " * "x"^200 for i in 1:100], "\n")  # Create longer lines
            write(test_file, test_content)

            chunker = FullFileChunker(max_tokens=200)
            chunks, sources = RAG.get_chunks(chunker, [test_file])

            @test length(chunks) > 1  # Should be split into multiple chunks
            @test all(occursin("test.txt:", source) for source in sources)
            @test all(contains(chunk, "Line") for chunk in chunks)
            
            # Check if the max tokens is respected
            @test all(estimate_tokens(chunk, chunker.estimation_method) <= chunker.max_tokens for chunk in chunks)
            
            # Check if line numbers are continuous
            for i in 2:length(sources)
                prev_end = parse(Int, split(split(sources[i-1], ':')[2], '-')[2])
                current_start = parse(Int, split(split(sources[i], ':')[2], '-')[1])
                @test current_start == prev_end + 1 || current_start == prev_end
            end
        end
    end

    @testset "Line number accuracy" begin
        mktempdir() do temp_dir
            test_file = joinpath(temp_dir, "test.txt")
            test_content = join(["Line $i" for i in 1:50], "\n")
            write(test_file, test_content)

            chunker = FullFileChunker(max_tokens=100)
            chunks, sources = RAG.get_chunks(chunker, [test_file])

            for (i, source) in enumerate(sources)
                file_path, line_range = split(source, ':')
                start_line, end_line = parse.(Int, split(line_range, '-'))
                
                @test start_line <= end_line
                @test end_line <= 50
                if i > 1
                    prev_file_path, prev_line_range = split(sources[i-1], ':')
                    _, prev_end_line = parse.(Int, split(prev_line_range, '-'))
                    @test start_line == prev_end_line + 1
                end
            end
        end
    end

    @testset "Multiple files handling" begin
        mktempdir() do temp_dir
            file1 = joinpath(temp_dir, "file1.txt")
            file2 = joinpath(temp_dir, "file2.txt")
            write(file1, join(["File1 Line $i" for i in 1:30], "\n"))
            write(file2, join(["File2 Line $i" for i in 1:20], "\n"))

            chunker = FullFileChunker(max_tokens=150)
            chunks, sources = RAG.get_chunks(chunker, [file1, file2])

            @test any(contains(source, "file1.txt") for source in sources)
            @test any(contains(source, "file2.txt") for source in sources)
            @test any(contains(chunk, "File1") for chunk in chunks)
            @test any(contains(chunk, "File2") for chunk in chunks)
        end
    end

    @testset "Empty file handling" begin
        mktempdir() do temp_dir
            empty_file = joinpath(temp_dir, "empty.txt")
            touch(empty_file)
            non_empty_file = joinpath(temp_dir, "nonempty.txt")
            write(non_empty_file, "content")

            chunker = FullFileChunker()
            chunks, sources = RAG.get_chunks(chunker, [empty_file, non_empty_file])

            @test length(chunks) == 2
            @test length(sources) == 2
            @test isempty(chunks[1])
            @test !isempty(chunks[2])
            @test sources[1] == empty_file
            @test sources[2] == non_empty_file

            # Check that empty files are processed without breaking the chain
            chunks, sources = RAG.get_chunks(chunker, [empty_file, non_empty_file, empty_file])
            @test length(chunks) == 3
            @test length(sources) == 3
            @test isempty(chunks[1])
            @test !isempty(chunks[2])
            @test isempty(chunks[3])
            @test sources[1] == empty_file
            @test sources[2] == non_empty_file
            @test sources[3] == empty_file
        end
    end

    @testset "reproduce_chunk functionality" begin
        mktempdir() do temp_dir
            test_file = joinpath(temp_dir, "test.txt")
            test_content = join(["Line $i" for i in 1:100], "\n")
            write(test_file, test_content)

            chunker = FullFileChunker(max_tokens=200)
            chunks, sources = RAG.get_chunks(chunker, [test_file])

            for source in sources
                reproduced_chunk = EasyContext.reproduce_chunk(chunker, source)
                @test !isempty(reproduced_chunk)
                @test contains(reproduced_chunk, "Line")

                # Check if the reproduced chunk matches the original chunk
                original_chunk = chunks[findfirst(==(source), sources)]
                @test strip(reproduced_chunk) == strip(original_chunk)
            end
        end
    end

    @testset "Large file handling" begin
        mktempdir() do temp_dir
            large_file = joinpath(temp_dir, "large.txt")
            large_content = join(["Long line of text: " * randstring(100) for _ in 1:1000], "\n")
            write(large_file, large_content)

            chunker = FullFileChunker(max_tokens=10000)
            chunks, sources = RAG.get_chunks(chunker, [large_file])

            @test length(chunks) > 1
            formatter_tokens = estimate_tokens(chunker.formatter("", ""), chunker.estimation_method)
            effective_max_tokens = chunker.max_tokens - formatter_tokens - chunker.line_number_token_estimate
            @test all(estimate_tokens(chunk, chunker.estimation_method) <= effective_max_tokens for chunk in chunks)
        end
    end

    @testset "Custom formatter" begin
        custom_formatter(source, content) = "SOURCE: $source\nCONTENT:\n$content"
        chunker = FullFileChunker(max_tokens=200, formatter=custom_formatter)
        
        mktempdir() do temp_dir
            test_file = joinpath(temp_dir, "test.txt")
            test_content = join(["Line $i" for i in 1:50], "\n")
            write(test_file, test_content)

            chunks, sources = RAG.get_chunks(chunker, [test_file])

            @test all(startswith(chunk, "SOURCE:") for chunk in chunks)
            @test all(contains(chunk, "CONTENT:") for chunk in chunks)
        end
    end

    @testset "Small file without line cuts" begin
        mktempdir() do temp_dir
            small_file = joinpath(temp_dir, "small.txt")
            small_content = "This is a small file that doesn't need to be split."
            write(small_file, small_content)

            chunker = FullFileChunker(max_tokens=1000)  # Large enough to fit the whole file
            chunks, sources = RAG.get_chunks(chunker, [small_file])

            @test length(chunks) == 1
            @test length(sources) == 1
            @test sources[1] == small_file  # Should not include line numbers
            @test chunks[1] == get_chunk_standard_format(small_file, small_content)
        end
    end

    @testset "Multiple files with mixed sizes" begin
        mktempdir() do temp_dir
            file1 = joinpath(temp_dir, "file1.txt")
            file2 = joinpath(temp_dir, "file2.txt")
            
            content1 = "Small file content"
            content2 = join(["Line $i" for i in 1:100], "\n")
            
            write(file1, content1)
            write(file2, content2)

            chunker = FullFileChunker(max_tokens=200)
            chunks, sources = RAG.get_chunks(chunker, [file1, file2])

            @test length(chunks) > 1
            @test any(source -> source == file1, sources)  # Small file should not have line numbers
            @test any(source -> occursin("file2.txt:", source), sources)  # Large file should have line numbers
        end
    end
end
;
