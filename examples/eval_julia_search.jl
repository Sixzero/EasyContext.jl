using EasyContext
using EasyContext: process_julia_context, init_julia_context, BM25Embedder, TopK
using Test
using JSON
using Dates

"""
    benchmark_julia_search(queries, models=["gem20f", "gpt4om"]; save_results=true)

Benchmark the JuliaSearchTool with different queries and models.
This function evaluates:
1. Response time
2. Result quality (by saving results for manual inspection)
3. Consistency across models

Parameters:
- `queries`: Array of search queries to test
- `models`: Array of reranker models to test
- `save_results`: Whether to save results to a JSON file for later analysis
"""
function benchmark_julia_search(queries, models=["gem20f", "gpt4om"]; save_results=true)
    results = Dict()
    
    for model in models
        model_results = Dict()
        println("\n=== Testing model: $model ===")
        
        # Initialize context with the current model
        julia_ctx = init_julia_context(; model=model, top_k=120)
        
        # Also create a baseline TopK search without reranking for comparison
        embedder = create_voyage_embedder(cache_prefix="juliapkgs")
        bm25 = BM25Embedder()
        topk_only = TopK([embedder, bm25]; top_k=120)
        
        for (i, query) in enumerate(queries)
            println("\nQuery $i: $query")
            
            # Measure time for full pipeline (TopK + reranking)
            rerank_time = @elapsed begin
                rerank_result, src_chunks = process_julia_context(julia_ctx, query)
            end
            
            # Measure time for just TopK
            topk_time = @elapsed begin
                topk_results = search(topk_only, src_chunks, query)
            end
            
            # Calculate result sizes
            rerank_size = length(rerank_result)
            topk_size = sum(length.(string.(topk_results)))
            
            # Store results
            query_result = Dict(
                "query" => query,
                "rerank_time" => rerank_time,
                "topk_time" => topk_time,
                "rerank_size" => rerank_size,
                "topk_size" => topk_size,
                "rerank_result" => rerank_result,
                "topk_sources" => [string(get_source(r)) for r in topk_results[1:min(10, length(topk_results))]]
            )
            
            model_results[query] = query_result
            
            # Print summary
            println("  Rerank time: $(round(rerank_time, digits=2))s, Result size: $rerank_size chars")
            println("  TopK time: $(round(topk_time, digits=2))s, Result size: $topk_size chars")
            println("  Speed improvement: $(round(rerank_time/topk_time, digits=2))x")
        end
        
        results[model] = model_results
    end
    
    if save_results
        timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
        filename = "julia_search_benchmark_$(timestamp).json"
        open(filename, "w") do io
            JSON.print(io, results, 2)  # Pretty print with indent=2
        end
        println("\nResults saved to $filename")
    end
    
    return results
end

"""
    evaluate_relevance(benchmark_results, ground_truth)

Evaluate the relevance of search results against ground truth.
This is a placeholder for a more sophisticated evaluation method.

Parameters:
- `benchmark_results`: Results from benchmark_julia_search
- `ground_truth`: Dictionary mapping queries to expected packages/functions
"""
function evaluate_relevance(benchmark_results, ground_truth)
    relevance_scores = Dict()
    
    for (model, model_results) in benchmark_results
        model_scores = Dict()
        
        for (query, query_result) in model_results
            if haskey(ground_truth, query)
                expected = ground_truth[query]
                result = query_result["rerank_result"]
                
                # Simple relevance check: do all expected terms appear in the result?
                matches = sum(term -> occursin(term, result), expected)
                score = matches / length(expected)
                
                model_scores[query] = score
            end
        end
        
        relevance_scores[model] = model_scores
    end
    
    return relevance_scores
end

# Sample test queries from TODO.jl
sample_queries = [
    "How to use BM25 for retrieval?",
    "How do we add KVCache ephemeral cache for API requests?",
    "How can we use DiffLib library in julia for reconstructing a 3rd file from 2 files?",
    "How to implement a Chunk struct which would hold context and source?",
    "How to use ReplMaker.jl to create a terminal for AI chat?",
    "What's the best way to parse JSON in Julia?",
    "How to implement multiple dispatch?",
    "What are efficient ways to work with DataFrames?",
    "How to create an HTTP server in Julia?",
    "What's the recommended way to handle concurrency in Julia?"
]

# Sample ground truth for relevance evaluation
# This would ideally be created by an expert or through a more rigorous process
sample_ground_truth = Dict(
    "How to use BM25 for retrieval?" => ["BM25", "TextAnalysis", "retrieval", "search"],
    "How to implement multiple dispatch?" => ["methods", "dispatch", "function"],
    "What's the best way to parse JSON in Julia?" => ["JSON", "parse", "Dict"],
    "How to create an HTTP server in Julia?" => ["HTTP.jl", "server", "route", "listen"]
)

"""
    run_benchmark()

Run the benchmark with sample queries and models.
"""
function run_benchmark()
    println("=== Julia Search Tool Benchmark ===")
    
    # Use a subset of models to keep runtime reasonable
    models = ["gem20f"]  # Add more models as needed: "gpt4om", "claudeh", etc.
    
    results = benchmark_julia_search(sample_queries, models)
    
    # Evaluate relevance if ground truth is available
    relevance = evaluate_relevance(results, sample_ground_truth)
    
    println("\n=== Relevance Scores ===")
    for (model, scores) in relevance
        println("Model: $model")
        for (query, score) in scores
            println("  Query: $query")
            println("  Score: $(round(score * 100))%")
        end
    end
    
    return results, relevance
end

# Only run the benchmark if this file is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_benchmark()
end
