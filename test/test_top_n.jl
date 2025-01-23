using Test
using EasyContext: topN

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
end
