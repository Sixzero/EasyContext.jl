using Test
using EasyContext
using JLD2
using Dates
using EasyContext: InstantApplyDiff

@testset "InstantApplyDiff Tests" begin
    # Setup test data
    test_dir = joinpath(@__DIR__, "..", "..", "data")
    test_file = joinpath(test_dir, "instant_apply_diffs.jld2")
    
    @testset "Read InstantApplyDiffs" begin
        mkpath(test_dir)
        # Create some test data first
        # log_instant_apply("original1", "proposed1", "test1.jl", "test question1")
        # log_instant_apply("original2", "proposed2", "test2.jl", "test question2")
        
        # sleep(0.1) # Wait for async operations
        
        # Read and verify the data
        jldopen(test_file, "r") do file
            @test haskey(file, "diffs")
            diffs = file["diffs"]
            
            # Test we have entries
            @test length(diffs) > 0
            
            # Check the latest entries
            latest = diffs["diff_$(length(diffs))"]
            @test latest isa InstantApplyDiff
            @test latest.original == "original2"
            @test latest.proposed == "proposed2"
            @test latest.filepath == "test2.jl"
            @test latest.question == "test question2"
            @test latest.timestamp isa DateTime
        end
    end

    @testset "Legacy Format Compatibility" begin
        # Test loading old format diffs
        legacy_diffs = load_instant_apply_diffs()
        @test length(legacy_diffs) > 0
        @test all(x -> x isa InstantApplyDiff, legacy_diffs)
        @test all(x -> x.question == "", filter(d -> d.timestamp < DateTime(2024,1,1), legacy_diffs))
    end
end
#%%
