using EasyContext
using DataFrames
using Random
using Statistics
using Dates
using Printf

"""
Simple benchmark to compare embedding speeds of OpenAI, Jina, Voyage, Cohere, and Google embedders.
"""
function run_simple_benchmark()
    # Create test datasets
    # Random.seed!(42)
    
    # Generate random text documents
    function generate_dataset(size, avg_length=1500)
        words = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", 
                "adipiscing", "elit", "sed", "do", "eiusmod", "tempor"]
        
        docs = String[]
        for i in 1:size
            doc = join([rand(words) for _ in 1:avg_length], " ")
            push!(docs, doc)
        end
        
        return docs
    end
    
    # Create small and large datasets
    small_dataset = generate_dataset(20)
    large_dataset = generate_dataset(100)
    
    # Create embedders with unique cache prefixes to avoid interference
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    prefix = "bench_$(timestamp)_"
    embedders = [
        # ("GoogleGecko", EasyContext.GoogleGeckoEmbedder(verbose=false, model="text-embedding-005")),
        # ("GoogleExp0307", EasyContext.GoogleGeckoEmbedder(; 
        #         model = "text-embedding-large-exp-03-07", 
        #         project_id=EasyContext.get_project_id(), location = "us-central1", task_type = "RETRIEVAL_DOCUMENT", 
        #         output_dimensionality = nothing, verbose = false)),
        # ("Voyage", EasyContext.VoyageEmbedder(; model="voyage-multimodal-3", input_type="document", verbose=false)),
        ("Voyage", EasyContext.VoyageEmbedder(; model="voyage-3.5-lite", verbose=false)),
        
        # ("Voyage", EasyContext.create_voyage_embedder(cache_prefix="bench_$(timestamp)_voyage_", verbose=false)),
        # ("Jina", EasyContext.create_jina_embedder(cache_prefix="bench_$(timestamp)_jina_")),
        # ("Cohere", EasyContext.create_cohere_embedder(model="embed-multilingual-v3.0", cache_prefix=prefix * "cohere_", verbose=false)),
        ("CohereEng", EasyContext.create_cohere_embedder(model="embed-v4.0", cache_prefix="bench_$(timestamp)_cohere_embed-v4.0_", verbose=false)),
        # ("CohereEng", EasyContext.create_cohere_embedder(model="embed-english-v3.0", cache_prefix="bench_$(timestamp)_cohere_eng_", verbose=false)),
        # ("GoogleMulti", EasyContext.create_google_multilingual_embedder(cache_prefix="bench_$(timestamp)_google_multi_", verbose=false)),
        # ("GooglePreview", EasyContext.create_google_preview_embedder(cache_prefix="bench_$(timestamp)_google_prev_", verbose=false)),
        
        # ("OpenAI", EasyContext.create_openai_embedder(cache_prefix="bench_$(timestamp)_openai_")),
        ("OpenAI", EasyContext.create_openai_embedder(cache_prefix=prefix * "openai_large", model="text-embedding-3-large")),
    ]
    
    # Results storage
    results = []
    
    println("=== EMBEDDING BENCHMARK ===")
    println("Testing $(length(embedders)) embedders with small (20 docs) and large (100 docs) datasets")
    
    # Run benchmarks
    for (name, embedder) in embedders
        println("\n--- $name ---")
        
        # Clear cache
        empty!(EasyContext.CACHE_STATE.cache)
        
        # Small dataset benchmark
        println("Small dataset (20 docs):")
        small_time = @elapsed small_result = EasyContext.get_embeddings_document(embedder, small_dataset)
        small_dims = size(small_result)
        small_throughput = 20 / small_time
        println("  Time: $(round(small_time, digits=2)) seconds")
        println("  Throughput: $(round(small_throughput, digits=2)) docs/sec")
        println("  Dimensions: $(small_dims[1])")
        
        # Clear cache
        empty!(EasyContext.CACHE_STATE.cache)
        
        # Large dataset benchmark
        println("Large dataset (100 docs):")
        large_time = @elapsed large_result = EasyContext.get_embeddings_document(embedder, large_dataset)
        large_dims = size(large_result)
        large_throughput = 100 / large_time
        println("  Time: $(round(large_time, digits=2)) seconds")
        println("  Throughput: $(round(large_throughput, digits=2)) docs/sec")
        println("  Dimensions: $(large_dims[1])")
        
        # Store results
        push!(results, (
            name = name,
            small_time = small_time,
            small_throughput = small_throughput,
            large_time = large_time,
            large_throughput = large_throughput,
            dimensions = small_dims[1]
        ))
    end
    
    # Print summary
    println("\n=== SUMMARY ===")
    println("Small dataset (20 docs) - fastest to slowest:")
    sort!(results, by = r -> r.small_time)
    for r in results
        println("  $(r.name): $(round(r.small_time, digits=2))s ($(round(r.small_throughput, digits=2)) docs/sec)")
    end
    
    println("\nLarge dataset (100 docs) - fastest to slowest:")
    sort!(results, by = r -> r.large_time)
    for r in results
        println("  $(r.name): $(round(r.large_time, digits=2))s ($(round(r.large_throughput, digits=2)) docs/sec)")
    end
    
    return results
end

# Run the benchmark
run_simple_benchmark()
;
#%%
using EasyContext
# embedder = EasyContext.create_cohere_embedder(cache_prefix="bench_test_cohere_", verbose=false)
# embedder = EasyContext.create_voyage_embedder(cache_prefix="bench_test_voyage_", verbose=false)
# embedder = EasyContext.create_google_gecko_embedder(cache_prefix="bench_test_googlegecko_", verbose=false)
# embedder = EasyContext.create_google_experimental_embedder(cache_prefix="bench_test_googlegecko_", verbose=false)
embedder = EasyContext.create_random_embedder(seed=42, cache_prefix="random2_precompile")
# embedder = EasyContext.VoyageEmbedder()
small_dataset = [join(["Hello, world $(rand(1:1000)) Igen, jó lenne tudni, hogy miért ilyen nagy! $i" for i in 1:22], "\n") for _ in 1:100]
tracker = Threads.Atomic{Float64}(0.0)
# @edit EasyContext.get_embeddings(embedder, small_dataset, tracker, 80_000, 4, NamedTuple())
# @code_warntype EasyContext.get_embeddings(embedder, small_dataset, tracker, 80_000, 4, NamedTuple())
@time small_result = EasyContext.get_embeddings(embedder, small_dataset, tracker, 80_000, 4, NamedTuple())
# EasyContext.get_project_id()
;

#%%
embedder = EasyContext.create_google_gecko_embedder(; 
                model = "text-embedding-large-exp-03-07", 
                project_id=EasyContext.get_project_id(), location = "us-central1", task_type = "RETRIEVAL_DOCUMENT", 
                output_dimensionality = nothing, verbose = false)
EasyContext.get_auth_token(embedder)