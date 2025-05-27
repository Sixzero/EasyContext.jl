using Test
using EasyContext: topN, TopN
using EasyContext: MaxScoreEmbedder, RRFScoreEmbedder, WeighterEmbedder

@testset "topN" begin
    # Test 1: Basic case (n < length)
    scores = [5.0, 2.0, 8.0, 1.0]
    chunks = ["a", "b", "c", "d"]
    n = 2
    expected = chunks[sortperm(scores, rev=true)][1:n]
    @test topN(scores, chunks, n) == expected

    # Test 2: n > length (return all sorted)
    scores = [3.0, 1.0]
    chunks = ["x", "y"]
    n = 5
    expected = chunks[sortperm(scores, rev=true)]
    @test topN(scores, chunks, n) == expected

    # Test 3: Empty input
    scores = Float64[]
    chunks = String[]
    n = 3
    @test topN(scores, chunks, n) == String[]

    # Test 4: Ties in scores
    scores = [10.0, 10.0, 5.0]
    chunks = ["α", "β", "γ"]
    n = 2
    expected = chunks[sortperm(scores, rev=true)][1:n]
    @test topN(scores, chunks, n) == expected

    # Test 5: n = 0 (edge case)
    scores = [7.0, 6.0, 5.0]
    chunks = [:a, :b, :c]
    n = 0
    @test topN(scores, chunks, n) == Symbol[]

    # Test 6: Exact match (n = length)
    scores = [9, 8, 7]
    chunks = [100, 200, 300]
    n = 3
    expected = chunks[sortperm(scores, rev=true)]
    @test topN(scores, chunks, n) == expected
    # Test 6: Exact match (n = length)
    scores = randn(1000)
    chunks = rand(1:100000, 1000)
    n = 300
    expected = chunks[sortperm(scores, rev=true)]
    results = topN(scores, chunks, n)
    @test results == expected[1:n]

    @testset "TopN struct" begin
        chunks = ["a", "b", "c", "d"]
        query = "test query"

        # Mock embedders
        mock1 = MockEmbedder([0.8, 0.3, 0.9, 0.1])
        mock2 = MockEmbedder([0.7, 0.8, 0.2, 0.9])
        
        # Test single embedder
        topn_single = TopN(mock1, n=2)
        result = topn_single(chunks, query)
        @test result == ["c", "a"]

        # Test weighted combination
        topn_weighted = TopN([mock1, mock2], weights=[0.7, 0.3], n=2)
        result_weighted = topn_weighted(chunks, query)
        @test length(result_weighted) == 2

        # Test max score combination
        topn_max = TopN([mock1, mock2], method=:max, n=2)
        result_max = topn_max(chunks, query)
        @test length(result_max) == 2

        # Test RRF combination
        topn_rrf = TopN([mock1, mock2], method=:rrf, n=2)
        result_rrf = topn_rrf(chunks, query)
        @test length(result_rrf) == 2
    end
end

# Mock embedder for testing
struct MockEmbedder <: RAGTools.AbstractEmbedder
    scores::Vector{Float64}
end

function get_score(embedder::MockEmbedder, chunks::AbstractVector{<:AbstractString}, query::AbstractString)
    embedder.scores
end
