using Test
using EasyContext
using JLD2
using Dates
using EasyContext: InstantApplyDiff, atomic_append_diff, load_instant_apply_diffs

@testset "InstantApplyDiff Tests" begin
    # Setup test data
    test_dir = joinpath(@__DIR__, "diffs")
    test_file = joinpath(test_dir, "test_instant_apply_diffs.jld2")
    
    @testset "Read InstantApplyDiffs" begin
        mkpath(test_dir)
        # Create test data
        diff1 = InstantApplyDiff(original="original1", proposed="proposed1", 
                                filepath="test1.jl", question="test question1")
        diff2 = InstantApplyDiff(original="original2", proposed="proposed2", 
                                filepath="test2.jl", question="test question2")
        
        # Clear test file if exists
        isfile(test_file) && rm(test_file)
        
        atomic_append_diff(diff1, test_file)
        atomic_append_diff(diff2, test_file)
        
        # Read and verify the data
        diffs = load_instant_apply_diffs(test_file)
        @test length(diffs) == 2
        
        # Check entries
        latest_key = maximum([parse(Int, split(k, "_")[end]) for k in keys(diffs)])
        latest = diffs["diffs/diff_$latest_key"]
        @test latest isa InstantApplyDiff
        @test latest.original == "original2"
        @test latest.proposed == "proposed2"
        @test latest.filepath == "test2.jl"
        @test latest.question == "test question2"
        @test latest.timestamp isa DateTime
        
        # Cleanup
        rm(test_file)
    end

    @testset "Legacy Format Compatibility" begin
        # Test loading old format diffs
        legacy_diffs = load_instant_apply_diffs()
        @test length(legacy_diffs) > 0
        # @test all(x -> x isa InstantApplyDiff, values(legacy_diffs))
    end
end;
#%%
using EasyContext: load_instant_apply_diffs, DEFAULT_DIFF_FILE, save_instant_apply_diffs
res = load_instant_apply_diffs()

k = "diffs/diff_36"
# k = "diffs/diff_39"
println(res[k].original)
@show "OK OTHER FILE"
println(res[k].proposed)
# for (k, v) in res
    # @show k, typeof(v)
# end
# save_instant_apply_diffs(res, DEFAULT_DIFF_FILE)