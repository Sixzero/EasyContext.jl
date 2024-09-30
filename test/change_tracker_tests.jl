
using Test
include("../src/transform/change_tracker.jl")
include("../src/ContextStructs.jl")

@testset "ChangeTracker tests" begin
    @testset "Basic functionality" begin
        tracker = ChangeTracker()
        src_content = Dict{String,String}(
            "file1.txt" => "content1",
            "file2.txt" => "content2"
        )
        
        # Mock the get_updated_content function
        global get_updated_content
        original_get_updated_content = get_updated_content
        get_updated_content(source::String) = source == "file1.txt" ? "content1" : "new_content2"

        updated_tracker, updated_content = tracker(src_content)

        @test length(updated_tracker) == 2
        @test updated_tracker["file1.txt"] == :NEW
        @test updated_tracker["file2.txt"] == :UPDATED
        @test updated_content == src_content

        # Restore the original function
        global get_updated_content = original_get_updated_content
    end

    @testset "Multiple updates" begin
        tracker = ChangeTracker()
        sources = ["./src/contexts/ContextNode.jl"]
        contexts = ["# Content of ContextNode.jl"]
        
        # First update
        src_content = Dict(sources[1] => contexts[1])
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker) == 1
        @test updated_tracker[sources[1]] == :NEW

        # Second update (no change)
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker) == 1
        @test updated_tracker[sources[1]] == :UNCHANGED

        # Third update (with change)
        new_context = "# Updated content of ContextNode.jl"
        src_content[sources[1]] = new_context
        get_updated_content(source::String) = new_context
        
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker) == 1
        @test updated_tracker[sources[1]] == :UPDATED

        # Restore the original function
        global get_updated_content = original_get_updated_content
    end
end

