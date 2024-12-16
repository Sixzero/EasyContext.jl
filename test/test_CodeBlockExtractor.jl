using Test
using EasyContext
using OrderedCollections
using EasyContext: CodeBlockExtractor, CodeBlock, extract_and_preprocess_codeblocks, reset!, to_string, SHELL_RUN_RESULT

@testset "CodeBlockExtractor Tests" begin
    @testset "Constructor" begin
        extractor = CodeBlockExtractor()
        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.command_tasks)
        @test isempty(extractor.shell_results)
        @test extractor.full_content == ""
        @test !extractor.skip_code_execution
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
            println("Hello, \$name!")
        end
        ```
        OK
        """
        
        result = extract_and_preprocess_codeblocks(content, extractor; instant_return=false)
        
        @test length(extractor.command_tasks) == 2
        @test extractor.last_processed_index[] == length(content)
    end


    @testset "reset!" begin
        extractor = CodeBlockExtractor()
        extractor.last_processed_index[] = 100
        extractor.command_tasks["test"] = @task nothing
        extractor.shell_results["test"] = CodeBlock(language="julia", file_path="test.jl", content="")
        extractor.full_content = "Some content"

        reset!(extractor)

        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.command_tasks)
        @test isempty(extractor.shell_results)
        @test extractor.full_content == ""
    end

    @testset "to_string" begin
        extractor = CodeBlockExtractor()
        cb1 = CodeBlock(type=:DEFAULT, language="julia", file_path="test1.jl", content="println(1)")
        cb2 = CodeBlock(type=:DEFAULT, language="python", file_path="test2.py", content="print(2)")
        push!(cb1.run_results, "1")
        push!(cb2.run_results, "2")
        extractor.shell_results["test1"] = cb1
        extractor.shell_results["test2"] = cb2

        result = to_string("ShellResults", "CommandTag", extractor)
        
        @test occursin("<ShellResults>", result)
        @test occursin("<CommandTag shortened>", result)
        @test occursin("<$SHELL_RUN_RESULT>", result)
        @test occursin("1", result)
        @test occursin("2", result)
    end

    @testset "Nested codeblocks" begin
        extractor = CodeBlockExtractor()
        content = """
        Some text before
        MODIFY ./test.jl
        ```julia
        function nested_block_example()
            println("Outer function")
            
            # Here's a nested codeblock
            code = ```julia
            function inner_function()
                println("Inner function")
            end
            inner_function()
            ```
            
            eval(Meta.parse(code))
        end
        
        nested_block_example()
        ```
        Some text after
        """
        
        result = extract_and_preprocess_codeblocks(content, extractor)
        
        @test result isa CodeBlock
        @test result.type == :MODIFY
        @test result.file_path == "./test.jl"
        @test result.language == "julia"
        @test occursin("function nested_block_example()", result.content)
        @test occursin("function inner_function()", result.content)
        @test occursin("nested_block_example()", result.content)
        @test length(extractor.command_tasks) == 1
        @test extractor.last_processed_index[] == length(content)
    end

    @testset "Nested codeblocks in documentation" begin
        extractor = CodeBlockExtractor()
        content = """
        Some text before
        MODIFY ./test.jl
        ```julia
        \"\"\"
        Documentation for a function with a code example:

        ```julia
        function example()
            println("This is an example")
        end
        ```

        And another example:

        ```python
        def another_example():
            print("This is another example")
        ```

        More documentation text.
        \"\"\"

        function outer_function()
            println("Outer function")
        end
        ```
        Some text after
        """
        
        result = extract_and_preprocess_codeblocks(content, extractor)
        
        @test result isa CodeBlock
        @test result.type == :MODIFY
        @test result.file_path == "./test.jl"
        @test result.language == "julia"
        @test occursin("Documentation for a function with a code example:", result.content)
        @test occursin("function example()", result.content)
        @test occursin("def another_example():", result.content)
        @test occursin("function outer_function()", result.content)
        @test length(extractor.command_tasks) == 1
        @test extractor.last_processed_index[] == length(content)
    end
end
;
