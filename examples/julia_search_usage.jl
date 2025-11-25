using EasyContext
using EasyContext: push_message!, BM25Embedder, TopK, julia_ctx_2_string, get_source

"""
This example demonstrates how to use JuliaSearchTool and JuliaCTX for searching Julia code.
"""

function demo_julia_search()
    println("\n=== Julia Search Demo ===")
    
    # Create agent with JuliaSearchTool
    agent = create_FluidAgent(
        "orqwenplus",  # Using a model that works well with code
        tools=[JuliaSearchTool,],
        create_sys_msg=() -> "You are a helpful assistant that can search for Julia code examples.",
    )

    # Try some searches
    queries = [
        "parse JSON in Julia",
        "how to work with DataFrames",
        "create HTTP server"
    ]

    for query in queries
        println("\nSearching for: $query")
        # Create a session for conversation
        session = Session()
    
        push_message!(session, create_user_message("Find Julia code examples for: $query"))
        response = work(agent, session, cache=false)
        println("\nAgent Response:")
        println(response.content)
    end
end

# Direct usage of JuliaCTX
function demo_direct_julia_ctx()
    println("=== Direct JuliaCTX Usage ===")
    # Try a search
    query = "parse JSON in Julia, most up to date"
    println("Searching for: $query")
    
    model="gem20p"
    model="orqwenplus"
    # model="claude"
    model="claudeh"
    model="gem20f"  # Using a code-specific model
    # model="gem20fl"
    # model="gem20ft"
    # model="dscode"
    # model="gpt4om"
    # model="o3m"
    # model="orqwenmax"
    # Initialize the context with reranker
    julia_ctx = init_julia_context(; model, top_k=120)
    
    # Create direct TopK search without reranker
    embedder = create_voyage_embedder(cache_prefix="juliapkgs")
    bm25 = BM25Embedder()
    topk_only = TopK([embedder, bm25]; top_k=120)
    
    # Get results with full pipeline (TopK + reranking)
    @time result_rerank, src_chunks = process_julia_context(julia_ctx, query)
    
    # Get results with just TopK
    @time topk_results = search(topk_only, src_chunks, query)
    @show sum(length.(string.(topk_results)))
    # println.(get_source.(topk_results))
    
    println("\n$model search results (with reranking):")
    println("Result string length: ", length(result_rerank))
end

# Run demos
function run_demos()
    println("Julia Search Examples")
    println("===================")
    
    # demo_julia_search()
    demo_direct_julia_ctx()
end

run_demos()
