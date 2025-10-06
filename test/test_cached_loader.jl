using Test
using EasyContext
using DataStructures: OrderedDict

@testset "CachedLoader" begin
    @testset "Basic Operations" begin
        embedder = BM25Embedder()
        cache = CachedLoader(loader=embedder, memory=Dict{String,Vector{Float64}}())
        chunks = ["test1", "test2"]
        query = "query"
        
        # Test get_score caching
        result1 = get_score(cache, chunks, query)
        result2 = get_score(cache, chunks, query)
        @test result1 == result2  # Same results from cache
        
        # Test different inputs give different results
        result3 = get_score(cache, ["different"], query)
        @test result1 != result3
    end

    @testset "Kwargs Handling" begin
        embedder = BM25Embedder()
        cache = CachedLoader(loader=embedder, memory=Dict{String,Vector{Float64}}())
        chunks = ["test1", "test2"]
        query = "query"
        
        # Test with cost_tracker
        cost_tracker1 = Threads.Atomic{Float64}(0.0)
        cost_tracker2 = Threads.Atomic{Float64}(0.0)
        
        result1 = get_score(cache, chunks, query; cost_tracker=cost_tracker1)
        result2 = get_score(cache, chunks, query; cost_tracker=cost_tracker2)
        
        @test result1 == result2  # Results should be same despite different cost_trackers
    end

    @testset "Cache Persistence" begin
        embedder = BM25Embedder()
        temp_dir = mktempdir()
        cache = CachedLoader(
            loader=embedder,
            cache_dir=temp_dir,
            memory=Dict{String,Vector{Float64}}()
        )
        
        chunks = ["persistence_test1", "persistence_test2"]
        query = "query"
        
        # First call - should compute and cache
        result1 = get_score(cache, chunks, query)
        
        # Create new cache with same dir but empty memory
        new_cache = CachedLoader(
            loader=embedder,
            cache_dir=temp_dir,
            memory=Dict{String,Vector{Float64}}()
        )
        
        # Should load from file cache
        result2 = get_score(new_cache, chunks, query)
        @test result1 == result2
        
        # Cleanup
        rm(temp_dir, recursive=true)
    end
end
