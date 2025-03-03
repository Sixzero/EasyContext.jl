using BenchmarkTools
using Statistics
using EasyContext
using Random
using PrettyTables

# Helper function to generate test data
function generate_test_data(n_embedders=3, n_chunks=1000)
    # Generate random scores for each embedder
    scores = [rand(Float64, n_chunks) for _ in 1:n_embedders]
    return scores
end

# Different implementations to test

# 1. Current zip-based implementation
function mean_scores_zip(scores)
    mean.(zip(scores...))
end

# 2. Direct array indexing
function mean_scores_index(scores)
    n = length(first(scores))
    [sum(s[i] for s in scores)/length(scores) for i in 1:n]
end

# 3. Matrix-based implementation
function mean_scores_matrix(scores)
    mat = reduce(hcat, scores)
    vec(mean(mat, dims=2))
end

# 4. Preallocated array implementation
function mean_scores_prealloc(scores)
    n = length(first(scores))
    n_scores = length(scores)
    result = zeros(n)
    for i in 1:n
        sum_scores = 0.0
        for s in scores
            sum_scores += s[i]
        end
        result[i] = sum_scores / n_scores
    end
    return result
end

# 5. SIMD optimized implementation
function mean_scores_simd(scores)
    n = length(first(scores))
    n_scores = length(scores)
    result = zeros(n)
    @simd for i in 1:n
        sum_scores = 0.0
        for s in scores
            @inbounds sum_scores += s[i]
        end
        @inbounds result[i] = sum_scores / n_scores
    end
    return result
end

function format_memory(bytes)
    if bytes < 1024
        return "$(round(Int, bytes))B"
    elseif bytes < 1024^2
        return "$(round(bytes/1024, digits=1))KB"
    else
        return "$(round(bytes/1024^2, digits=1))MB"
    end
end

function run_benchmarks()
    # Test scenarios
    scenarios = [
        (3, 100),    # Small case
        # (3, 1000),   # Medium case
        # (3, 10000),  # Large case
        # (5, 1000),   # More embedders
        # (10, 1000),  # Many embedders
    ]

    println("Running benchmarks for different mean score implementations...")
    println("=======================================================")

    for (n_embedders, n_chunks) in scenarios
        println("\nScenario: $n_embedders embedders, $n_chunks chunks")
        println("-------------------------------------------------------")

        scores = generate_test_data(n_embedders, n_chunks)

        # Verify all implementations give same results
        results = [
            mean_scores_zip(scores),
            mean_scores_index(scores),
            mean_scores_matrix(scores),
            mean_scores_prealloc(scores),
            mean_scores_simd(scores)
        ]
        
        # Verify all implementations give the same results
        @assert all(r ≈ results[1] for r in results[2:end]) "Implementation results differ!"

        # Benchmark each implementation
        b_zip = @benchmark mean_scores_zip($scores)
        b_index = @benchmark mean_scores_index($scores)
        b_matrix = @benchmark mean_scores_matrix($scores)
        b_prealloc = @benchmark mean_scores_prealloc($scores)
        b_simd = @benchmark mean_scores_simd($scores)

        # Create matrix for pretty table
        data = Matrix{Any}(undef, 5, 5)
        data[1,:] = ["Zip-based", "$(round(minimum(b_zip).time/1000, digits=1))μs", "$(round(mean(b_zip).time/1000, digits=1))μs", format_memory(b_zip.memory), b_zip.allocs]
        data[2,:] = ["Direct index", "$(round(minimum(b_index).time/1000, digits=1))μs", "$(round(mean(b_index).time/1000, digits=1))μs", format_memory(b_index.memory), b_index.allocs]
        data[3,:] = ["Matrix-based", "$(round(minimum(b_matrix).time/1000, digits=1))μs", "$(round(mean(b_matrix).time/1000, digits=1))μs", format_memory(b_matrix.memory), b_matrix.allocs]
        data[4,:] = ["Preallocated", "$(round(minimum(b_prealloc).time/1000, digits=1))μs", "$(round(mean(b_prealloc).time/1000, digits=1))μs", format_memory(b_prealloc.memory), b_prealloc.allocs]
        data[5,:] = ["SIMD optimized", "$(round(minimum(b_simd).time/1000, digits=1))μs", "$(round(mean(b_simd).time/1000, digits=1))μs", format_memory(b_simd.memory), b_simd.allocs]

        # Print results table
        pretty_table(
            data,
            header=["Implementation", "Min Time", "Mean Time", "Memory", "Allocations"],
            alignment=[:l, :r, :r, :r, :r],
            crop=:none
        )
    end
end

run_benchmarks()
