using EasyContext
using EasyContext: process_workspace_context, init_workspace_context
using Test
using JSON
using Dates
using Statistics

"""
    benchmark_workspace_search(test_cases, models; save_results=true)

Benchmark the WorkspaceSearchTool with different queries and expected results.
This function evaluates recall, precision, and F1 score across different models.

Parameters:
- `test_cases`: Array of tuples (repo_path, query, expected_files)
- `models`: Array of reranker models to test
- `save_results`: Whether to save results to a JSON file
"""
function benchmark_workspace_search(test_cases, models; save_results=true)
    results = Dict()
    
    for model in models
        model_results = Dict()
        println("\n=== Testing model: $model ===")
        
        metrics = Dict(
            "recall" => Float64[],
            "precision" => Float64[],
            "f1_score" => Float64[],
            "time" => Float64[]
        )
        
        for (repo_path, query, expected_files) in test_cases
            # Initialize workspace context and measure search time
            workspace_ctx = init_workspace_context([repo_path]; model, top_k=50, verbose=false)
            search_time = @elapsed begin
                _, file_chunks, file_chunks_reranked = process_workspace_context(workspace_ctx, query)
            end
            
            # Extract returned file paths directly from chunks
            returned_files = unique([chunk.source.path for chunk in file_chunks_reranked])
            @show returned_files
            @show expected_files
            
            # Calculate metrics with smart path matching
            recall, precision, f1 = calculate_metrics(expected_files, returned_files)
            
            # Store metrics
            push!(metrics["recall"], recall)
            push!(metrics["precision"], precision)
            push!(metrics["f1_score"], f1)
            push!(metrics["time"], search_time)
            
            # Store detailed results
            query_key = "$(basename(repo_path)): $(first(split(query, '\n')))"
            model_results[query_key] = Dict(
                "repo_path" => repo_path,
                "query" => query,
                "expected_files" => expected_files,
                "returned_files" => returned_files,
                "search_time" => search_time,
                "recall" => recall,
                "precision" => precision,
                "f1_score" => f1
            )
            
            # Print summary
            println("  Recall: $(round(recall * 100))%, Precision: $(round(precision * 100))%, F1: $(round(f1 * 100))% Time: $(round(search_time, digits=2))s")
        end
        
        # Calculate and store average metrics
        avg_metrics = Dict(k => mean(v) for (k, v) in metrics)
        model_results["average_metrics"] = avg_metrics
        results[model] = model_results
        
        # Print model summary
        println("\n=== Model Summary: $model ===")
        println("  Avg Recall: $(round(avg_metrics["recall"] * 100, digits=1))%")
        println("  Avg Precision: $(round(avg_metrics["precision"] * 100, digits=1))%")
        println("  Avg F1 Score: $(round(avg_metrics["f1_score"] * 100, digits=1))%")
        println("  Avg Search Time: $(round(avg_metrics["time"], digits=2))s")
    end
    
    # Save results if requested
    if save_results
        timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
        filename = "workspace_search_benchmark_$(timestamp).json"
        open(filename, "w") do io
            JSON.print(io, results, 2)
        end
        println("\nResults saved to $filename")
    end
    
    return results
end

"""
    calculate_metrics(expected_files, returned_files)

Calculate recall, precision, and F1 score using smart path matching.
"""
function calculate_metrics(expected_files, returned_files)
    # Normalize paths for comparison
    norm_expected = normalize_paths.(expected_files)
    norm_returned = normalize_paths.(returned_files)
    
    # Find matches using smart path matching
    matches = Set{String}()
    for expected in norm_expected
        for returned in norm_returned
            if is_path_match(expected, returned)
                push!(matches, returned)
                break
            end
        end
    end
    
    # Calculate metrics
    true_positives = length(matches)
    recall = isempty(norm_expected) ? 1.0 : true_positives / length(norm_expected)
    precision = isempty(norm_returned) ? 1.0 : true_positives / length(norm_returned)
    f1 = (recall + precision == 0) ? 0.0 : 2 * (precision * recall) / (precision + recall)
    
    return recall, precision, f1
end

"""
    normalize_paths(path)

Normalize file paths for consistent comparison.
"""
function normalize_paths(path)
    path = startswith(path, "./") ? path[3:end] : path
    path = replace(path, "\\" => "/")
    return occursin(':', path) ? first(split(path, ':')) : path
end

"""
    is_path_match(path1, path2)

Determine if two paths likely refer to the same file.
"""
function is_path_match(path1, path2)
    # match one path ends with the other
    return endswith(path1, path2) || 
           endswith(path2, path1)
end

"""
    run_benchmark(test_cases, models=["gem20f"])

Run the benchmark with the provided test cases and models.
"""
function run_benchmark(test_cases, models=["gem20f"])
    println("=== Workspace Search Benchmark ===")
    results = benchmark_workspace_search(test_cases, models)
    
    println("\n=== Overall Results ===")
    for (model, model_results) in results
        avg = model_results["average_metrics"]
        println("Model: $model")
        println("  Avg Recall: $(round(avg["recall"] * 100, digits=1))%")
        println("  Avg Precision: $(round(avg["precision"] * 100, digits=1))%")
        println("  Avg F1 Score: $(round(avg["f1_score"] * 100, digits=1))%")
    end
    
    return results
end

"""
    create_reranker_optimizer(reranker_fn)

Create a wrapper around a reranker function that analyzes performance and suggests improvements.
This is a higher-order function that returns an optimized reranker function.
"""
function create_reranker_optimizer(reranker_fn; model="gpt4o")
    return function optimized_reranker(chunks, query, expected_targets=nothing; kwargs...)
        # Call the original reranker
        reranked_chunks = reranker_fn(chunks, query; kwargs...)
        
        # If we have expected targets, analyze performance
        if !isnothing(expected_targets)
            reranked_paths = [chunk.source.path for chunk in reranked_chunks]
            
            # Find missing targets
            missing_targets = filter(target -> 
                !any(is_path_match(target, path) for path in reranked_paths), 
                expected_targets)
            
            if !isempty(missing_targets)
                println("\nReranker optimization analysis:")
                println("  Query: $query")
                println("  Missing targets: $(join(missing_targets, ", "))")
                
                # Analyze each missing target
                for target in missing_targets
                    target_chunks = filter(chunk -> 
                        any(is_path_match(target, chunk.source.path)), 
                        chunks)
                    
                    if !isempty(target_chunks)
                        reason = analyze_target_omission(target, target_chunks, query, model)
                        println("  - $target: $reason")
                    else
                        println("  - $target: Not found in original chunks")
                    end
                end
                
                # In a full implementation, suggest prompt improvements
                # suggest_prompt_improvements(chunks, reranked_chunks, missing_targets, query, model)
            end
        end
        
        return reranked_chunks
    end
end

# Test cases
monaco_meld_test_cases = [
    (
        "/home/six/repo/monaco-meld/",
        """Please implement window.electronAPI.getAppVersion?.() with the tools you have modify the necessary files to make it work. in preload.cjs
        const { contextBridge, ipcRenderer } = require('electron');

        // Forward console messages from main to renderer
        ipcRenderer.on('console-log', (event, ...args) => {
        console.log('[Main Process]:', ...args);
        });

        ipcRenderer.on('console-error', (event, ...args) => {
        console.error('[Main Process]:', ...args);
        });

        // Expose protected methods that allow the renderer process to use
        // the ipcRenderer without exposing the entire object
        contextBridge.exposeInMainWorld(
        'electronAPI', {
            port: process.env.PORT || '3000',
            focusWindow: () => ipcRenderer.invoke('focus-window'),
            showSaveDialog: (options) => ipcRenderer.invoke('show-save-dialog', options),
            
            // Add method to get app version from package.json
            // getAppVersion: () => get version
        }
        );""",
        ["preload.cjs", "src/renderer/ui/emptyState.js", "main.cjs", "package.json", "renderer.js"]
    ),
    (
        "/home/six/repo/monaco-meld/",
        "Please implement window.electronAPI.getAppVersion?.() with the tools you have modify the necessary files to make it work.",
        ["preload.cjs", "src/renderer/ui/emptyState.js", "main.cjs", "package.json", "renderer.js"]
    ),
    (
        "/home/six/repo/monaco-meld/",
        "Please implement window.electronAPI.getAppVersion?.() with the tools you have modify the necessary files to make it work. in preload.cjs",
        ["preload.cjs", "src/renderer/ui/emptyState.js", "main.cjs", "package.json", "renderer.js"]
    )
]

# "dscode",                 # a little too slow.
# "gem20p", "gemexp",       # these might get RESOURCE_EXHAUSTED
# "orqwenmax", "mistrall"   # Max 32k context window
# run_benchmark(monaco_meld_test_cases, ["gem20f", "gem20fl", "orqwenplus", "claude", ])
# run_benchmark(monaco_meld_test_cases, ["orqwenplus", "orqwenturbo", "minimax"])
# run_benchmark(monaco_meld_test_cases, ["mistralc", "mistralm"])
# run_benchmark(monaco_meld_test_cases, ["claudeh", "claude35"])
# run_benchmark(monaco_meld_test_cases, ["claudeh"])
# run_benchmark(monaco_meld_test_cases, ["gem20f",])
;
