using Test
using EasyContext
using DataStructures: OrderedDict

@testset failfast=true "Reranker Tests" begin
    @testset "Batching Strategies" begin
        docs = [
            "short doc",  # ~10 tokens
            "x" ^ 1000,   # ~350 tokens
            "y" ^ 2000,   # ~700 tokens
            "z" ^ 3000,   # ~1050 tokens
            "a" ^ 100     # ~35 tokens
        ]
        query = "test query"

        @testset "TokenBalancedBatcher" begin
            strategy = EasyContext.TokenBalancedBatcher()
            batches = EasyContext.create_batches(
                strategy, 
                docs, 
                query,
                EasyContext.create_rankgpt_prompt_v2,
                1000,  # max_tokens
                3,     # batch_size
                verbose=2
            )
            
            # Test batch properties
            @test length(batches) ≥ 2  # Should create at least 2 batches
            @test all(b -> length(b) ≤ 3, batches)  # Respect batch_size
            
            # Test token balancing
            first_batch_docs = docs[batches[1]]
            @test any(d -> length(d) > 1000, first_batch_docs)  # Largest docs should be in first batch
        end

        @testset "LinearGrowthBatcher" begin
            strategy = EasyContext.LinearGrowthBatcher()
            batches = EasyContext.create_batches(
                strategy, 
                docs, 
                query,
                EasyContext.create_rankgpt_prompt_v2,
                1000,  # max_tokens
                3,     # batch_size
                verbose=2
            )
            
            # Test batch properties
            @test length(batches) ≥ 2  # Should create at least 2 batches
            @test all(b -> length(b) ≤ 3, batches)  # Respect batch_size
            
            
        end

    end

    @testset "ReduceGPTReranker Integration" begin
        docs = [
            "\nfunction add(x) = x + 1",         # Most relevant
            "\nfunction subtract(x) = x - 1",     # Less relevant
            "\nfunction multiply(x) = x * 2",     # Less relevant
            "\nstruct Calculator x::Int end",     # Not relevant
            "\n# Helper\nfunction helper() = 0"   # Not relevant
        ]
        chunks = OrderedDict(zip(string.(1:5), docs))
        query = "I need a function that adds 1 to a number"

        @testset "Basic reranking" begin
            reranker = EasyContext.ReduceGPTReranker(
                batch_size=2,
                top_n=2,
                model="dscode",
                verbose=2
            )
            result = reranker(chunks, query)
            
            @test length(result) == 2  # Should return top 2 results
            @test haskey(result, "1")  # Should include the add function
        end

        @testset "Different batch sizes" begin
            for batch_size in [2, 3, 5]
                reranker = EasyContext.ReduceGPTReranker(
                    batch_size=batch_size,
                    top_n=2,
                    model="dscode",
                    verbose=2
                )
                result = reranker(chunks, query)
                @test length(result) == 2
            end
        end

        @testset "Different batching strategies" begin
            reranker = EasyContext.ReduceGPTReranker(
                batch_size=2,
                top_n=2,
                model="dscode",
                batching_strategy=EasyContext.LinearGrowthBatcher(),
                verbose=2
            )
            result_linear = reranker(chunks, query)
            
            # Test with TokenBalancedBatcher
            reranker = EasyContext.ReduceGPTReranker(
                batch_size=2,
                top_n=2,
                model="dscode",
                batching_strategy=EasyContext.TokenBalancedBatcher(),
                verbose=2
            )
            result_balanced = reranker(chunks, query)
            
            @test length(result_linear) == length(result_balanced) == 2
        end

        @testset "Edge cases" begin
            # Single document
            single_doc = OrderedDict("1" => "\nfunction add(x) = x + 1")
            reranker = EasyContext.ReduceGPTReranker(batch_size=2, top_n=2)
            result = reranker(single_doc, query)
            @test length(result) == 1
            
            # Empty query
            result = reranker(chunks, "")
            @test !isempty(result)
            
            # Large batch size
            reranker = EasyContext.ReduceGPTReranker(batch_size=10, top_n=2)
            result = reranker(chunks, query)
            @test length(result) == 2
        end
    end
    @testset "Humanization" begin
        reranker = EasyContext.ReduceGPTReranker(model="dscode", batch_size=3, top_n=2)
        humanized = EasyContext.humanize(reranker)
        @test contains(humanized, "dscode")
        @test contains(humanized, "3")
        @test contains(humanized, "2")
        
        simple_reranker = EasyContext.SimpleGPTReranker(model="dscode")
        simple_humanized = EasyContext.humanize(simple_reranker)
        @test contains(simple_humanized, "dscode")
        @test contains(simple_humanized, "SimpleGPT")
    end
end
