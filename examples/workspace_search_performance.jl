using EasyContext
using EasyContext: init_workspace_context, process_workspace_context, EFFICIENT_PIPELINE
using EasyContext: Context, ChangeTracker, FileChunk
using BenchmarkTools
using Statistics

println("=== Workspace Search Performance Test ===")

# Configuration
# folder_path = expanduser("~/repo/todoforai/frontend")
folder_path = expanduser("~/repo/todoforai/edge")
pipeline = EFFICIENT_PIPELINE(model=["google-ai-studio:google/gemini-2.5-flash-preview-09-2025"], verbose=2)
verbose = false

println("Folder: $folder_path")
println("Pipeline: EFFICIENT_PIPELINE")
println()

# Test queries
test_queries = [
    "API endpoints",
    "authentication logic",
    "tauri configuration",
    "React components",
    "database schema",
]

const tracker_context = Context{FileChunk}()
const changes_tracker = ChangeTracker{FileChunk}()
# Initialize workspace context
println("Initializing workspace context...")
init_time = @elapsed workspace_ctx = init_workspace_context([folder_path]; 
                                                           pipeline=pipeline, 
                                                           verbose=verbose,
                                                           tracker_context, changes_tracker)
println("Workspace initialization time: $(round(init_time, digits=3))s")
println()

# Run tests for each query
results = []
for (i, query) in enumerate(test_queries)
    println("[$i/$(length(test_queries))] Testing query: \"$query\"")
    
    # Benchmark the search
    search_time = @elapsed begin
        result, chunks, reranked, full_result = process_workspace_context(workspace_ctx, query)
    end
    
    # Get timing breakdown from pipeline
    search_phase_time = pipeline.search_times[end]
    rerank_phase_time = pipeline.rerank_times[end]
    
    # Get metrics
    num_chunks = isnothing(chunks) ? 0 : length(chunks)
    num_reranked = isnothing(reranked) ? 0 : length(reranked)
    cost = isnothing(full_result) ? 0.0 : full_result.cost
    result_length = length(result)
    has_results = !isempty(result)
    
    push!(results, (
        query = query,
        search_time = search_time,
        search_phase_time = search_phase_time,
        rerank_phase_time = rerank_phase_time,
        num_chunks = num_chunks,
        num_reranked = num_reranked,
        cost = cost,
        result_length = result_length,
        has_results = has_results
    ))
    
    println("  Total time: $(round(search_time, digits=3))s")
    println("    Search phase: $(round(search_phase_time, digits=3))s")
    println("    Rerank phase: $(round(rerank_phase_time, digits=3))s")
    println("  Chunks: $num_chunks → $num_reranked")
    println("  Cost: \$$(round(cost, digits=4))")
    println("  Result length: $result_length chars")
    println("  Has results: $has_results")
    println()
end

# Performance summary
println("=== Performance Summary ===")
search_times = [r.search_time for r in results]
search_phase_times = [r.search_phase_time for r in results]
rerank_phase_times = [r.rerank_phase_time for r in results]
costs = [r.cost for r in results]

println("Total search times:")
println("  Mean: $(round(mean(search_times), digits=3))s")
println("  Median: $(round(median(search_times), digits=3))s")
println("  Min: $(round(minimum(search_times), digits=3))s")
println("  Max: $(round(maximum(search_times), digits=3))s")
println()

println("Search phase times:")
println("  Mean: $(round(mean(search_phase_times), digits=3))s")
println("  Median: $(round(median(search_phase_times), digits=3))s")
println("  Min: $(round(minimum(search_phase_times), digits=3))s")
println("  Max: $(round(maximum(search_phase_times), digits=3))s")
println()

println("Rerank phase times:")
println("  Mean: $(round(mean(rerank_phase_times), digits=3))s")
println("  Median: $(round(median(rerank_phase_times), digits=3))s")
println("  Min: $(round(minimum(rerank_phase_times), digits=3))s")
println("  Max: $(round(maximum(rerank_phase_times), digits=3))s")
println()

# Show phase breakdown as percentages
search_percentage = mean(search_phase_times ./ search_times) * 100
rerank_percentage = mean(rerank_phase_times ./ search_times) * 100
println("Phase breakdown (average):")
println("  Search: $(round(search_percentage, digits=1))%")
println("  Rerank: $(round(rerank_percentage, digits=1))%")
println()

println("Costs:")
println("  Total: \$$(round(sum(costs), digits=4))")
println("  Mean: \$$(round(mean(costs), digits=4))")
println("  Median: \$$(round(median(costs), digits=4))")
println()

successful_queries = sum([r.has_results for r in results])
println("Success rate: $successful_queries/$(length(test_queries)) ($(round(100*successful_queries/length(test_queries), digits=1))%)")
