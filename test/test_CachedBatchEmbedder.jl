using Test
using EasyContext
using DataStructures: OrderedDict
using EasyContext: EmbedderSearch, OpenAIBatchEmbedder, CachedBatchEmbedder, JinaEmbedder, VoyageEmbedder, CombinedIndexBuilder
using EasyContext: BM25Embedder
using EasyContext: get_index
using HTTP
using PromptingTools.Experimental.RAGTools
using JSON3
using Chairmarks
using BenchmarkTools
using Random

@testset "CachedBatchEmbedder Tests" begin
    @testset "Constructor" begin
        embedder = CachedBatchEmbedder()
        @test embedder isa CachedBatchEmbedder
        @test embedder.embedder isa OpenAIBatchEmbedder
        @test isdir(embedder.cache_dir)
    end

    @testset "Cache Management" begin
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

        # Create test embedder
        mock_embedder = MockEmbedder()
        embedder = CachedBatchEmbedder(embedder=mock_embedder)
        test_docs = ["doc1", "doc2", "doc3"]
        
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
        emb3 = get_embeddings(embedder, ["doc1", "doc4"])
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
        cache_file = joinpath(embedder.cache_dir, "embeddings_mock-embedder.jld2")
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
        embedder = CachedBatchEmbedder(embedder=EmbedderSearch(embedder=VoyageEmbedder()))
        docs = ["This is a test document", "Another test document", "Third test document"]

        # Mock the HTTP.post function to avoid actual API calls
        function mock_http_post(url, headers, body)
            parsed_body = JSON3.read(body)
            mock_response = Dict(
                "data" => [Dict("embedding" => rand(Float32, 1536)) for _ in 1:length(parsed_body["input"])]
            )
            return HTTP.Response(200, JSON3.write(mock_response))
        end

        # Override the http_post function in the embedder
        embedder.embedder.embedder.http_post = mock_http_post

        # Warmup
        get_embeddings(embedder, docs)

        # Benchmark
        b = @b get_embeddings(embedder, docs)
        @info "CachedBatchEmbedder performance:" b

        # Check if results are cached
        cache_file = joinpath(embedder.cache_dir, "embeddings_OpenAIBatchEmbedder_text-embedding-3-small.jld2")
        @test isfile(cache_file)

        # Benchmark with cached results
        b_cached = @b get_embeddings(embedder, docs)
        @info "CachedBatchEmbedder performance (cached):" b_cached

        @test b_cached.time < b.time  # Cached should be faster

        # Type stability check
        @inferred get_embeddings(embedder, docs)

        # Check output type and dimensions
        result = get_embeddings(embedder, docs)
        @test result isa Matrix{Float32}
        @test size(result, 2) == length(docs)
        @test size(result, 1) == 1536  # Assuming OpenAI's text-embedding-3-small returns 1536-dimensional embeddings
    end
end

;
