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

        # Second run with some changes
        new_src_content = Dict{String,String}(
            "source1" => "content1",
            "source2" => "updated_content2",
            "source4" => "content4"
        )
        result = tracker(new_src_content; max_history=2)
        @test length(tracker.tracker) == 4
        @test tracker.tracker["source1"] == 2
        @test tracker.tracker["source2"] == 2
        @test tracker.tracker["source3"] == 1
        @test tracker.tracker["source4"] == 1
        @test length(result) == 3
        @test !haskey(result, "source3")
        @test result["source2"] == "updated_content2"
        @test result["source4"] == "content4"

        # Third run
        final_src_content = Dict{String,String}(
            "source2" => "updated_content2",
            "source4" => "updated_content4",
            "source5" => "content5"
        )
        result = tracker(final_src_content; max_history=2)
        @test length(tracker.tracker) == 3
        @test !haskey(tracker.tracker, "source1")
        @test tracker.tracker["source2"] == 3
        @test tracker.tracker["source4"] == 2
        @test tracker.tracker["source5"] == 1
        @test length(result) == 3
        @test !haskey(result, "source1")
        @test !haskey(result, "source3")
        @test result["source2"] == "updated_content2"
        @test result["source4"] == "updated_content4"
        @test result["source5"] == "content5"
    end

    @testset "Refresh specific sources" begin
        tracker = AgeTracker()
        src_content = OrderedDict{String,String}(
            "source1" => "content1",
            "source2" => "content2",
            "source3" => "content3"
        )
        
        # First run
        result = tracker(src_content; max_history=3)
        @test all(age == 1 for age in values(tracker.tracker))

        # Second run
        result = tracker(src_content; max_history=3)
        @test all(age == 2 for age in values(tracker.tracker))

        # Third run with refresh
        refresh_these = OrderedDict{String,String}(
            "source1" => "",
            "source3" => ""
        )
        result = tracker(src_content; max_history=3, refresh_these=refresh_these)
        @test tracker.tracker["source1"] == 1
        @test tracker.tracker["source2"] == 3
        @test tracker.tracker["source3"] == 1

        # Fourth run
        result = tracker(src_content; max_history=3)
        @test tracker.tracker["source1"] == 2
        @test !haskey(tracker.tracker, "source2")  # Should be removed due to max_history
        @test tracker.tracker["source3"] == 2
    end
end

