using Test
using EasyContext
using DataStructures: OrderedDict
using EasyContext: EmbeddingIndexBuilder, OpenAIBatchEmbedder, CachedBatchEmbedder, JinaEmbedder, VoyageEmbedder, CombinedIndexBuilder
using EasyContext: BM25IndexBuilder
using EasyContext: get_index
using HTTP
using PromptingTools.Experimental.RAGTools
using JSON3
using Chairmarks
using BenchmarkTools


@testset "CachedBatchEmbedder Tests" begin
    @testset "Constructor" begin
        embedder = CachedBatchEmbedder()
        @test embedder isa CachedBatchEmbedder
        @test embedder.embedder isa OpenAIBatchEmbedder
        @test isdir(embedder.cache_dir)
    end

    @testset "Performance and Type Stability" begin
        embedder = CachedBatchEmbedder(embedder=EmbeddingIndexBuilder(embedder=VoyageEmbedder()))
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
