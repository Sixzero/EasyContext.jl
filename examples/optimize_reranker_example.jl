using EasyContext
using EasyContext: process_workspace_context, init_workspace_context, get_chunks, FullFileChunker
using Test
using JSON
using Dates
using Statistics


"""
    run_optimized_search(test_cases, model="gem20f")

Runs workspace search with an optimized reranker and analyzes missed targets.
"""
run_optimized_search(test_cases, model="gem20f") = begin
    println("=== Optimized Workspace Search ===")
    for (repo_path, query, expected_files) in test_cases
        println("\nQuery: $query")
        workspace_ctx = init_workspace_context([repo_path]; model, top_k=50, verbose=false)
        original_reranker(chunks, query; kwargs...) = search(workspace_ctx.rag_pipeline, chunks, query; kwargs...)
        optimized_reranker = optimize_reranker(original_reranker; model="gpt4o")
        all_chunks = get_chunks(FullFileChunker(), workspace_ctx.workspace)
        reranked_chunks = optimized_reranker(all_chunks, query, expected_files)
        println("Returned files: ", unique([c.source.path for c in reranked_chunks]))
    end
end

# Test cases
monaco_meld_test_cases = [
    (
        "/home/six/repo/monaco-meld/",
        "Implement window.electronAPI.getAppVersion?.()",
        ["preload.cjs", "src/renderer/ui/emptyState.js", "main.cjs", "package.json", "renderer.js"]
    )
]

run_optimized_search(monaco_meld_test_cases)
