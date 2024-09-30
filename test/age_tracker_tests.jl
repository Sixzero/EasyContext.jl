using Test
include("../src/filters/AgeTracker.jl")
include("../src/ContextStructs.jl")

@testset "AgeTracker tests" begin
    @testset "Basic functionality" begin
        tracker = AgeTracker()
        src_content = Dict{String,String}(
            "source1" => "content1",
            "source2" => "content2",
            "source3" => "content3"
        )
        
        # First run
        result = tracker(src_content; max_history=2)
        @test length(tracker.tracker) == 3
        @test all(age == 1 for age in values(tracker.tracker))
        @test result == src_content

        # Second run
        result = tracker(Dict("source1" => "content1", "source2" => "content2"); max_history=2)
        @test length(tracker.tracker) == 3
        @test tracker.tracker["source1"] == 2
        @test tracker.tracker["source2"] == 2
        @test tracker.tracker["source3"] == 1
        @test length(result) == 2
        @test !haskey(result, "source3")

        # Third run
        result = tracker(Dict("source2" => "content2", "source4" => "content4"); max_history=2)
        @test length(tracker.tracker) == 3
        @test !haskey(tracker.tracker, "source1")
        @test tracker.tracker["source2"] == 3
        @test tracker.tracker["source3"] == 1
        @test tracker.tracker["source4"] == 1
        @test length(result) == 2
        @test !haskey(result, "source1")
    end

    @testset "Cut history functionality" begin
        tracker = AgeTracker()
        sources = ["./src/contexts/ContextNode.jl", "./src/contexts/ContextProcessors.jl"]
        contexts = ["# Content of ContextNode.jl", "# Content of ContextProcessors.jl"]
        
        for i in 1:5
            src_content = Dict(sources[1] => contexts[1] * " $i")
            tracker(src_content; max_history=10)
        end
        src_content = Dict(sources[2] => contexts[2])
        tracker(src_content; max_history=10)
        
        @test length(tracker.tracker) == 2
        
        result = tracker(src_content; max_history=3)
        
        @test length(tracker.tracker) == 1
        @test haskey(tracker.tracker, sources[2])
        @test !haskey(tracker.tracker, sources[1])
        @test length(result) == 1
        @test haskey(result, sources[2])
    end
end

