using Test
using EasyContext
using OrderedCollections

@testset "CodeBlockExtractor Tests" begin
    @testset "Constructor" begin
        extractor = CodeBlockExtractor()
        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.shell_scripts)
        @test isempty(extractor.shell_results)
        @test extractor.full_content == ""
        @test !extractor.skip_code_execution
        @test !extractor.no_confirm
    end

    @testset "extract_and_preprocess_codeblocks" begin
        extractor = CodeBlockExtractor()
        content = """
        Some text before
        MODIFY ./test.jl
        ```julia
        println("Hello, World!")
        ```
        Some text after
        CREATE ./new_file.jl
        ```julia
        function greet(name)
            println("Hello, $name!")
        end
        ```
        """
        
        result = extract_and_preprocess_codeblocks(content, extractor)
        
        @test result isa CodeBlock
        @test length(extractor.shell_scripts) == 2
        @test extractor.last_processed_index[] == length(content)
    end

    @testset "reset!" begin
        extractor = CodeBlockExtractor()
        extractor.last_processed_index[] = 100
        extractor.shell_scripts["test"] = @task nothing
        extractor.shell_results["test"] = CodeBlock(language="julia", file_path="test.jl", pre_content="")
        extractor.full_content = "Some content"

        reset!(extractor)

        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.shell_scripts)
        @test isempty(extractor.shell_results)
        @test extractor.full_content == ""
    end

    @testset "to_string" begin
        extractor = CodeBlockExtractor()
        cb1 = CodeBlock(language="julia", file_path="test1.jl", pre_content="println(1)")
        cb2 = CodeBlock(language="python", file_path="test2.py", pre_content="print(2)")
        push!(cb1.run_results, "1")
        push!(cb2.run_results, "2")
        extractor.shell_results["test1"] = cb1
        extractor.shell_results["test2"] = cb2

        result = to_string("ShellResults", "Command", extractor)
        
        @test occursin("<ShellResults>", result)
        @test occursin("<Command shortened>", result)
        @test occursin("<SHELL_RUN_RESULT>", result)
        @test occursin("1", result)
        @test occursin("2", result)
    end
end
