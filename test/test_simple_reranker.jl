using Test
using EasyContext
using DataStructures: OrderedDict

@testset "SimpleGPTReranker Tests" begin
    docs = [
        "\nfunction add(x) = x + 1",         # Relevant
        "\nfunction subtract(x) = x - 1",     # Not relevant
        "\nfunction multiply(x) = x * 2",     # Not relevant
        "\nstruct Calculator x::Int end",     # Not relevant
        "\n# Helper\nfunction helper() = 0"   # Not relevant
    ]
    chunks = OrderedDict(zip(string.(1:5), docs))
    query = "I need a function that adds 1 to a number"

    @testset "Basic reranking" begin
        reranker = SimpleGPTReranker(model="dscode", verbose=2)
        result = reranker(chunks, query)
        
        @test !isempty(result)
        @test haskey(result, "1")  # Should include the add function
    end

    @testset "Edge cases" begin
        reranker = SimpleGPTReranker()
        
        # Single document
        single_doc = OrderedDict("1" => "\nfunction add(x) = x + 1")
        result = reranker(single_doc, query)
        @test length(result) == 1
        
        # Empty query
        result = reranker(chunks, "")
        @test isa(result, OrderedDict)
        
        # Irrelevant query
        result = reranker(chunks, "How to make a sandwich?")
        @test isa(result, OrderedDict)
    end
end
