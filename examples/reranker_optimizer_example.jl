using EasyContext
using EasyContext.PromptOptimizer

# Define a test case
function run_optimized_search()
    println("=== Testing Reranker Optimizer ===")
    
    # Initialize workspace context
    repo_path = "/home/six/repo/EasyContext.jl/"
    query = "How does the workspace search tool work?"
    expected_files = ["src/tools/WorkspaceSearchTool.jl", "src/contexts/CTX_workspace.jl"]
    
    # Create workspace context
    workspace_ctx = init_workspace_context([repo_path]; model="gem20f", top_k=50, verbose=false)
    
    # Define original reranker function
    function original_reranker(chunks, query; kwargs...)
        return search(workspace_ctx.rag_pipeline, chunks, query; kwargs...)
    end
    
    # Create optimized reranker
    optimized_reranker = optimize_reranker(original_reranker; model="gpt4o")
    
    # Get all chunks
    all_chunks = get_chunks(FullFileChunker(), workspace_ctx.workspace)
    
    # Run optimized reranker with expected targets
    println("\nRunning optimized reranker with expected targets...")
    reranked_chunks = optimized_reranker(all_chunks, query, expected_files)
    
    # Print results
    println("\nReturned files:")
    returned_files = unique([chunk.source.path for chunk in reranked_chunks])
    for file in returned_files
        println("  - $file")
    end
    
    return reranked_chunks
end

# Run the example
run_optimized_search()
