using Test
using EasyContext
using DataStructures: OrderedDict
using EasyContext: CachedBatchEmbedder, get_embedder, create_voyage_embedder, OpenAIBatchEmbedder, BM25Embedder
using EasyContext: get_embedder_uniq_id
using HTTP
using PromptingTools.Experimental.RAGTools
using JSON3
using Chairmarks
using BenchmarkTools
using Random
using Distributed  # Added for @spawn

@testset failfast=true "CachedBatchEmbedder Tests" begin
    @testset "Constructor" begin
        embedder = CachedBatchEmbedder()
        @test embedder isa CachedBatchEmbedder
        @test embedder.embedder isa OpenAIBatchEmbedder
        @test isdir(embedder.cache_dir)
    end

    @testset "Cache Management" begin
        Random.seed!(time_ns())
        # Setup mock embedder
        mutable struct MockEmbedder <: RAGTools.AbstractEmbedder
            calls::Int
            dims::Int
            model::String
            uniq_id::String
            MockEmbedder() = new(0, 4, "mock-model", "mock-embedder")
        end
        
        function EasyContext.get_embeddings(embedder::MockEmbedder, docs::AbstractVector{<:AbstractString}; kwargs...)
            embedder.calls += 1
            return rand(Float32, embedder.dims, length(docs))
        end
        EasyContext.get_model_name(e::MockEmbedder) = e.model
        EasyContext.get_embedder_uniq_id(e::MockEmbedder) = e.uniq_id
        EasyContext.get_embedder(e::MockEmbedder) = e

        # Create test embedder
        mock_embedder = MockEmbedder()
        embedder = CachedBatchEmbedder(embedder=mock_embedder)
        
        # Add random numbers to ensure uniqueness
        test_docs = ["doc1_$(rand(1:99999))", "doc2_$(rand(1:99999))", "doc3_$(rand(1:99999))"]
        
        # First call should use the mock embedder
        emb1 = get_embeddings(embedder, test_docs)
        @test mock_embedder.calls == 1
        @test size(emb1) == (mock_embedder.dims, length(test_docs))
        
        # Second call with same docs should use cache
        emb2 = get_embeddings(embedder, test_docs)
        @test mock_embedder.calls == 1  # No new calls
        @test size(emb2) == size(emb1)
        @test all(emb2 .== emb1)  # Should return exactly same embeddings
        
        # Call with new docs should partially use cache
        new_docs = [test_docs[1], "doc4_$(rand(1:99999))"]
        emb3 = get_embeddings(embedder, new_docs)
        @test mock_embedder.calls == 2  # One new call for "doc4"
        @test size(emb3) == (mock_embedder.dims, 2)
        @test emb3[:, 1] == emb1[:, 1]  # First doc should be from cache
    end

    @testset "Thread Safety" begin
        mock_embedder = MockEmbedder()
        embedder = CachedBatchEmbedder(embedder=mock_embedder)
        
        # Test concurrent embedding requests
        n_threads = 10
        docs_per_thread = ["thread$(i)_doc$(j)" for i in 1:n_threads for j in 1:3]
        
        tasks = [@spawn get_embeddings(embedder, docs_per_thread) for _ in 1:n_threads]
        results = fetch.(tasks)
        
        # All results should have same dimensions
        @test all(size(r) == size(first(results)) for r in results)
        
        # Cache file should exist
        cache_file = joinpath(embedder.cache_dir, "embeddings_mock-embedder.arrow")  # Changed from .jld2 to .arrow
        @test isfile(cache_file)
    end

    @testset "Cache Persistence" begin
        mock_embedder = MockEmbedder()
        cache_dir = mktempdir()
        
        # First embedder instance
        embedder1 = CachedBatchEmbedder(embedder=mock_embedder, cache_dir=cache_dir)
        docs = ["persistent_doc1", "persistent_doc2"]
        emb1 = get_embeddings(embedder1, docs)
        
        # Second embedder instance should use the same cache
        embedder2 = CachedBatchEmbedder(embedder=mock_embedder, cache_dir=cache_dir)
        emb2 = get_embeddings(embedder2, docs)
        
        @test all(emb1 .== emb2)
        @test mock_embedder.calls == 1  # Only one call should have been made
        
        # Cleanup
        rm(cache_dir, recursive=true)
    end

    @testset "Performance and Type Stability" begin
        embedder = create_voyage_embedder(model="voyage-code-3", verbose=false)
        docs = ["This is a test document", "Another test document", "Third test document"]

        # Mock the HTTP.post function to avoid actual API calls
        function mock_http_post(url, headers, body)
            parsed_body = JSON3.read(body)
            dim = 1024  # voyage-code-3 dimension
            mock_response = Dict(
                "data" => [Dict("embedding" => rand(Float32, dim)) for _ in 1:length(parsed_body["input"])],
                "usage" => Dict("total_tokens" => 100)
            )
            return HTTP.Response(200, JSON3.write(mock_response))
        end

        voyage_embedder = get_embedder(embedder.embedder)
        voyage_embedder.http_post = mock_http_post

        # Create two embedders with different cache prefixes
        uncached_embedder = CachedBatchEmbedder(embedder=embedder.embedder, cache_prefix="uncached_test_")
        cached_embedder = CachedBatchEmbedder(embedder=embedder.embedder, cache_prefix="cached_test_")

        # Get cache files for both
        uncached_file = joinpath(uncached_embedder.cache_dir, "uncached_test_embeddings_$(get_embedder_uniq_id(embedder)).arrow")
        cached_file = joinpath(cached_embedder.cache_dir, "cached_test_embeddings_$(get_embedder_uniq_id(embedder)).arrow")

        # Benchmark uncached with file and memory cache removal
        b_uncached = @benchmark get_embeddings($uncached_embedder, $docs) setup=(rm($uncached_file, force=true); empty!(EasyContext.CACHE_STATE.cache)) samples=5 seconds=1

        # Warmup and benchmark cached
        result = get_embeddings(cached_embedder, docs)
        b_cached = @benchmark get_embeddings($cached_embedder, $docs) samples=5 seconds=1

        @test minimum(b_cached).time < minimum(b_uncached).time  # Cached should be faster

        # Type stability check
        @inferred get_embeddings(cached_embedder, docs)

        # Check output type and dimensions
        result = get_embeddings(cached_embedder, docs)
        @test result isa Matrix{Float32}
        @test size(result, 2) == length(docs)
        @test size(result, 1) == 1024

        # Cleanup
        rm(uncached_file, force=true)
        rm(cached_file, force=true)
    end

    
end
