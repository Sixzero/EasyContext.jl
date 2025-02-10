using Test
using EasyContext
using DataStructures: OrderedDict
using EasyContext: CachedBatchEmbedder, get_embedder, create_voyage_embedder, OpenAIBatchEmbedder, BM25Embedder
using EasyContext: get_embedder_uniq_id, PartialEmbeddingResults, CACHE_STATE
using HTTP
using PromptingTools.Experimental.RAGTools
using JSON3
using Chairmarks
using BenchmarkTools
using Random
using Distributed  # Added for @spawn

@testset failfast=true "CachedBatchEmbedder Tests" begin
    @testset "Partial Embedding Results" begin
        # Mock embedder that fails for specific documents
        mutable struct PartialFailureEmbedder <: RAGTools.AbstractEmbedder
            fail_indices::Set{Int}
            dims::Int
            model::String
            uniq_id::String
            PartialFailureEmbedder(fail_indices) = new(Set(fail_indices), 4, "partial-mock", "partial-mock")
        end
        EasyContext.get_embedder(e::PartialFailureEmbedder) = e
        
        function EasyContext.get_embeddings(embedder::PartialFailureEmbedder, docs::AbstractVector{<:AbstractString}; kwargs...)
            # Create successful embeddings
            successful_results = Dict{Int, Vector{Float32}}()
            failed_indices = Int[]
            
            for (i, doc) in enumerate(docs)
                if i ∉ embedder.fail_indices
                    successful_results[i] = rand(Float32, embedder.dims)
                else
                    push!(failed_indices, i)
                end
            end
            
            if !isempty(failed_indices)
                throw(PartialEmbeddingResults(successful_results, failed_indices, ErrorException("Simulated failure")))
            end
            
            result = zeros(Float32, embedder.dims, length(docs))
            for (i, emb) in successful_results
                result[:, i] = emb
            end
            return result
        end
        EasyContext.get_model_name(e::PartialFailureEmbedder) = e.model
        EasyContext.get_embedder_uniq_id(e::PartialFailureEmbedder) = e.uniq_id

        # Test partial failure handling
        @testset "Partial Failure Recovery" begin
            fail_indices = [2, 4]  # Make documents 2 and 4 fail
            mock_embedder = PartialFailureEmbedder(fail_indices)
            cache_dir = mktempdir()
            embedder = CachedBatchEmbedder(embedder=mock_embedder, cache_dir=cache_dir, verbose=false)
            
            test_docs = ["doc1", "doc2", "doc3", "doc4", "doc5"]
            
            # First attempt should partially fail but cache successful results
            @test_throws Exception begin
                get_embeddings(embedder, test_docs)
            end
            
            # Check if successful embeddings were cached
            cache_file = joinpath(cache_dir, "embeddings_partial-mock.arrow")  # Changed to match embedder's uniq_id
            # @test isfile(cache_file)
            
            # Second attempt should use cached results and only try failed docs
            @test_throws Exception begin
                get_embeddings(embedder, test_docs)
            end
            
            # Try with only successful docs
            successful_docs = test_docs[[1,3,5]]
            result = get_embeddings(embedder, successful_docs)
            @test size(result) == (mock_embedder.dims, length(successful_docs))
            
            # Cleanup
            rm(cache_dir, recursive=true)
        end

        @testset "Cache Persistence After Partial Failure" begin
            fail_indices = [3]
            mock_embedder = PartialFailureEmbedder(fail_indices)
            cache_dir = mktempdir()
            embedder = CachedBatchEmbedder(embedder=mock_embedder, cache_dir=cache_dir, verbose=false)
            
            test_docs = ["doc1", "doc2", "doc3"]
            
            # First attempt - should fail for doc3 but cache doc1 and doc2
            @test_throws Exception get_embeddings(embedder, test_docs)
            
            cache_file = joinpath(cache_dir, "embeddings_partial-mock.arrow")  # Changed to match embedder's uniq_id
            @show isfile(cache_file)
            lock_key = get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)
            lock(lock_key) do
                # Just acquire and release to ensure previous writes completed
            end
            # Verify that successful embeddings were cached
            cache = EasyContext.load_cache(cache_file)
            @show cache
            @test length(cache) == 2  # Should have cached 2 documents
            
            # Try getting embeddings for just the successful docs
            successful_result = get_embeddings(embedder, test_docs[1:2])
            @test size(successful_result) == (mock_embedder.dims, 2)
            
            # Cleanup
            rm(cache_dir, recursive=true)
        end

        @testset "Batch Processing with Partial Failures" begin
            # Create a mock embedder that fails for specific batches
            mutable struct BatchFailureEmbedder <: RAGTools.AbstractEmbedder
                fail_batches::Set{Int}
                dims::Int
                model::String
                uniq_id::String
                BatchFailureEmbedder(fail_batches) = new(Set(fail_batches), 4, "batch-mock", "batch-mock")
            end
            
            function EasyContext.get_embeddings(embedder::BatchFailureEmbedder, docs::AbstractVector{<:AbstractString}; kwargs...)
                if length(docs) == 1 && rand() < 0.5  # Simulate random batch failure
                    # Instead of throwing generic error, throw PartialEmbeddingResults
                    successful_results = Dict{Int, Vector{Float32}}()
                    # Process all docs except the failing one
                    for i in 1:length(docs)-1
                        successful_results[i] = rand(Float32, embedder.dims)
                    end
                    throw(PartialEmbeddingResults(
                        successful_results,
                        [length(docs)],
                        ErrorException("Random batch failure")
                    ))
                end
                return rand(Float32, embedder.dims, length(docs))
            end
            EasyContext.get_model_name(e::BatchFailureEmbedder) = e.model
            EasyContext.get_embedder_uniq_id(e::BatchFailureEmbedder) = e.uniq_id

            mock_embedder = BatchFailureEmbedder([2])  # Fail second batch
            cache_dir = mktempdir()
            embedder = CachedBatchEmbedder(embedder=mock_embedder, cache_dir=cache_dir, verbose=false)
            
            # Create enough docs to force multiple batches
            test_docs = ["doc$i" for i in 1:10]
            
            # Should handle batch failures and cache successful results
            @test_throws Exception get_embeddings(embedder, test_docs)
            
            # Wait for any pending cache writes to complete
            cache_file = joinpath(cache_dir, "embeddings_batch-mock.arrow")
            lock_key = get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)
            lock(lock_key) do
                # Just acquire and release to ensure previous writes completed
            end
            
            # Now verify cache exists and has content
            @test isfile(cache_file)
            cache = EasyContext.load_cache(cache_file)
            @test !isempty(cache)
            
            # Cleanup
            rm(cache_dir, recursive=true)
        end
    end
end
