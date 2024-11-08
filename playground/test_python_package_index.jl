using Test
using PromptingTools
using PromptingTools.Experimental.RAGTools: get_chunks, SimpleIndexer, build_index
using EasyContext: GolemSourceChunker, CachedBatchEmbedder, NoSimilarityCheck, build_package_index

@testset "Python Package Index Creation" begin

    # Build index for AoE2ScenarioParser (main package) and DataStructures (utility package)
    packages = ["AoE2ScenarioParser", "DataStructures"]
    index = build_package_index(packages; verbose=true)
#%%
    # Tests
    @test !isnothing(index)
    @test length(index.chunks) > 0
    @test length(index.sources) == length(index.chunks)
    
    # Test content of chunks for AoE2ScenarioParser
    aoe2_chunks = filter(chunk -> occursin("AoE2ScenarioParser", chunk), index.chunks)
    @test !isempty(aoe2_chunks)
    @test any(chunk -> occursin("class Scenario", chunk), aoe2_chunks)
    @test any(chunk -> occursin("def get_scenario_metadata", chunk), aoe2_chunks)

    # Test content of chunks for DataStructures
    ds_chunks = filter(chunk -> occursin("DataStructures", chunk), index.chunks)
    @test !isempty(ds_chunks)
    @test any(chunk -> occursin("struct Deque", chunk), ds_chunks)
    @test any(chunk -> occursin("function push!", chunk), ds_chunks)

    # Test that chunks are properly separated
    @test all(chunk -> !(occursin("class Scenario", chunk) && occursin("struct Deque", chunk)), index.chunks)
end

