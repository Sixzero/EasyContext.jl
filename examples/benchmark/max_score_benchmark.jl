using BenchmarkTools
using Statistics
using EasyContext
using Random
using PrettyTables

# Helper function to generate test data
function generate_test_data(n_embedders=3, n_chunks=1000)
    [rand(Float64, n_chunks) for _ in 1:n_embedders]
end

# 1. Current implementation (list comprehension)
function max_scores_list(scores)
    n = length(first(scores))
    [maximum(s[i] for s in scores) for i in 1:n]
end

# 2. Matrix-based implementation
function max_scores_matrix(scores)
    mat = reduce(hcat, scores)
    vec(maximum(mat, dims=2))
end

# 3. Preallocated array implementation
function max_scores_prealloc(scores)
    n = length(first(scores))
    result = zeros(n)
    for i in 1:n
        max_score = -Inf
        for s in scores
            max_score = max(max_score, s[i])
        end
        result[i] = max_score
    end
    return result
end

# 4. SIMD optimized implementation
function max_scores_simd(scores)
    n = length(first(scores))
    result = zeros(n)
    @simd for i in 1:n
        max_score = -Inf
        for s in scores
            @inbounds max_score = max(max_score, s[i])
        end
        @inbounds result[i] = max_score
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
    scenarios = [
        (3, 100),    # Small case
        (3, 1000),   # Medium case
        (3, 10000),  # Large case
        (5, 1000),   # More embedders
        (10, 1000),  # Many embedders
    ]

    println("Running benchmarks for different max score implementations...")
    println("=======================================================")

    for (n_embedders, n_chunks) in scenarios
        println("\nScenario: $n_embedders embedders, $n_chunks chunks")
        println("-------------------------------------------------------")

        scores = generate_test_data(n_embedders, n_chunks)

        # Verify all implementations give same results
        results = [
            max_scores_list(scores),
            max_scores_matrix(scores),
            max_scores_prealloc(scores),
            max_scores_simd(scores)
        ]
        
        # Verify all implementations give the same results
        @assert all(r ≈ results[1] for r in results[2:end]) "Implementation results differ!"

        # Benchmark each implementation
        b_list = @benchmark max_scores_list($scores)
        b_matrix = @benchmark max_scores_matrix($scores)
        b_prealloc = @benchmark max_scores_prealloc($scores)
        b_simd = @benchmark max_scores_simd($scores)

        # Create matrix for pretty table
        data = Matrix{Any}(undef, 4, 5)
        data[1,:] = ["List comp", "$(round(minimum(b_list).time/1000, digits=1))μs", "$(round(mean(b_list).time/1000, digits=1))μs", format_memory(b_list.memory), b_list.allocs]
        data[2,:] = ["Matrix-based", "$(round(minimum(b_matrix).time/1000, digits=1))μs", "$(round(mean(b_matrix).time/1000, digits=1))μs", format_memory(b_matrix.memory), b_matrix.allocs]
        data[3,:] = ["Preallocated", "$(round(minimum(b_prealloc).time/1000, digits=1))μs", "$(round(mean(b_prealloc).time/1000, digits=1))μs", format_memory(b_prealloc.memory), b_prealloc.allocs]
        data[4,:] = ["SIMD optimized", "$(round(minimum(b_simd).time/1000, digits=1))μs", "$(round(mean(b_simd).time/1000, digits=1))μs", format_memory(b_simd.memory), b_simd.allocs]

        # Print results table
        pretty_table(
            data,
            header=["Implementation", "Min Time", "Mean Time", "Memory", "Allocations"],
            alignment=[:l, :r, :r, :r, :r],
            crop=:none
        )
    end
end

# Run benchmarks
run_benchmarks()
