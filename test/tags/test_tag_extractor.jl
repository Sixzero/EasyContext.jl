using Test
using EasyContext: TagExtractor
using EasyContext: Tag, extract_and_process_tags, reset!, to_string

@testset "TagExtractor Tests" begin
    @testset "Constructor" begin
        extractor = TagExtractor()
        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.tag_tasks)
        @test isempty(extractor.tag_results)
        @test extractor.full_content == ""
        @test !extractor.skip_execution
    end

    @testset "extract_and_process_tags" begin
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
        
        result = extract_and_process_tags(content, extractor; instant_return=false)
        
        @test length(extractor.tag_tasks) == 2
        # @test extractor.last_processed_index[] == length(content) # this is not neceessary.
    end

    @testset "reset!" begin
        extractor = TagExtractor()
        extractor.last_processed_index[] = 100
        extractor.tag_tasks["test"] = @task nothing
        extractor.tag_results["test"] = Tag("TEST", String[], Dict(), "")
        extractor.full_content = "Some content"

        reset!(extractor)

        @test extractor.last_processed_index[] == 0
        @test isempty(extractor.tag_tasks)
        @test isempty(extractor.tag_results)
        @test extractor.full_content == ""
    end

    @testset "to_string" begin
        extractor = TagExtractor()
        tag1 = Tag("SHELL", String[], Dict("result" => "output1"), "command1")
        tag2 = Tag("TEST", String[], Dict("result" => "output2"), "command2")
        extractor.tag_results["command1"] = tag1
        extractor.tag_results["command2"] = tag2

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
        
        @test_throws ErrorException extract_and_process_tags(content, extractor)
    end

end
