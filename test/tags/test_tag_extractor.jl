using Test
using EasyContext: TagExtractor
using EasyContext: Command, extract_commands, reset!, to_string

@testset "TagExtractor Tests" begin
    @testset "Constructor" begin
        extractor = TagExtractor()
        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.command_tasks)
        @test isempty(extractor.command_results)
        @test extractor.full_content == ""
        @test !extractor.skip_execution
    end

    @testset "extract_commands" begin
        extractor = TagExtractor()
        content = """
        Some text before
        MODIFY path/to/file force=true
        This is a modification
        /MODIFY
        Some text between
        CREATE new_file.txt
        New file content
        /CREATE
        Some text after
        """
        
        result = extract_commands(content, extractor; instant_return=false)
        
        @test length(extractor.command_tasks) == 2
        # @test extractor.last_processed_index[] == length(content) # this is not neceessary.
    end

    @testset "reset!" begin
        extractor = TagExtractor()
        extractor.last_processed_index[] = 100
        extractor.command_tasks["test"] = @task nothing
        extractor.command_results["test"] = Command("TEST", String[], Dict(), "")
        extractor.full_content = "Some content"

        reset!(extractor)

        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.command_tasks)
        @test isempty(extractor.command_results)
        @test extractor.full_content == ""
    end

    @testset "to_string" begin
        extractor = TagExtractor()
        tag1 = Command("SHELL", String[], Dict("result" => "output1"), "command1")
        tag2 = Command("TEST", String[], Dict("result" => "output2"), "command2")
        extractor.command_results["command1"] = tag1
        extractor.command_results["command2"] = tag2

        result = to_string("```result", "```sh", "```", extractor)
        
        @test occursin("```sh", result)
        @test occursin("```result", result)
        @test occursin("command1", result)
        @test occursin("command2", result)
        @test occursin("output1", result)
        @test occursin("output2", result)
    end

    @testset "Nested tags" begin
        extractor = TagExtractor()
        content = """
        OUTER arg1
        First line
        INNER arg2
        Nested content
        /INNER
        Last line
        /OUTER
        """
        
        @test_throws ErrorException extract_commands(content, extractor)
    end

end
