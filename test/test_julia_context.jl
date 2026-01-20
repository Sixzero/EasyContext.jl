using Test
using EasyContext
using DataStructures: OrderedDict

@testset "process_julia_context tests" begin
    @testset "Initial call" begin
        # Mock dependencies
        mock_jl_simi_filter = (index, query) -> OrderedDict("file1.jl" => "content1", "file2.jl" => "content2")
        mock_jl_reranker_filterer = (chunks, query) -> OrderedDict("file1.jl" => "content1", "file2.jl" => "content2")
        mock_tracker_context = identity
        mock_changes_tracker = identity
        mock_julia_ctx_2_string = (changes, content) -> "mock_result"

        julia_context = (
            jl_simi_filter = mock_jl_simi_filter,
            jl_pkg_index = nothing,
            tracker_context = mock_tracker_context,
            changes_tracker = mock_changes_tracker,
            jl_reranker_filterer = mock_jl_reranker_filterer,
            formatter = mock_julia_ctx_2_string,
        )

        result = process_julia_context(julia_context, "test query")
        
        @test result == "mock_result"
        # Add more specific assertions based on the expected behavior
    end

    @testset "Multiple calls mocked" begin
        call_count = Ref(0)
        
        function mock_jl_simi_filter(index, query)
            call_count[] += 1
            if call_count[] == 1
                return OrderedDict("file1.jl" => "content1", "file2.jl" => "content2")
            else
                return OrderedDict("file1.jl" => "content1", "file2.jl" => "content2", "file3.jl" => "content3")
            end
        end

        mock_jl_reranker_filterer = (chunks, query) -> chunks  # Pass through for simplicity
        mock_tracker_context = identity
        mock_changes_tracker = identity
        mock_julia_ctx_2_string = (changes, content) -> join(keys(content), ",")

        julia_context = (
            jl_simi_filter = mock_jl_simi_filter,
            jl_pkg_index = nothing,
            tracker_context = mock_tracker_context,
            changes_tracker = mock_changes_tracker,
            jl_reranker_filterer = mock_jl_reranker_filterer,
            formatter = mock_julia_ctx_2_string,
        )

        # First call
        result1 = process_julia_context(julia_context, "test query 1")
        @test result1 == "file1.jl,file2.jl"

        # Second call
        result2 = process_julia_context(julia_context, "test query 2")
        @test result2 == "file1.jl,file2.jl,file3.jl"
    end

    @testset "Multiple calls to process_julia_context" begin
        # Initialize the julia_context
        julia_context = init_julia_context()

        # Prepare some test queries
        queries = [
            "How to use arrays in Julia?",
            "What are the best practices for writing efficient Julia code?",
            "How to implement multiple dispatch in Julia?"
        ]

        # Store results for each query
        results = []

        for (i, query) in enumerate(queries)
            result = process_julia_context(julia_context, query)
            push!(results, result)

            # Print some information about the result
            println("Query $i: $query")
            println("Number of chunks: $(count(x -> x == '\n', result) + 1)")
            println("---")

            # Basic tests
            @test !isempty(result)
            @test result isa String
            @test occursin("<JuliaFunctions", result)  # Check if the result contains the expected tag
        end

        # Test that results are different for different queries
        @test length(unique(results)) == length(queries)

        # Test that the number of chunks doesn't decrease in subsequent calls
        chunk_counts = [count(x -> x == '\n', result) + 1 for result in results]
        @test issorted(chunk_counts, rev=true)

        # Optional: Test with source_tracker
        source_tracker = SourceTracker()
        result_with_source_tracker = process_julia_context(julia_context, "How does garbage collection work in Julia?", source_tracker=source_tracker)
        @test !isempty(result_with_source_tracker)
    end
end
@testset "JuliaCTX Tests" begin
    @testset "Lazy Index Initialization" begin
        # Initialize context
        julia_ctx = init_julia_context(verbose=false)

        # Check that index is initially nothing
        @test isnothing(julia_ctx.jl_pkg_index)

        # Process a query which should trigger index creation
        result = process_julia_context(julia_ctx, "How to use arrays?")

        # Check that index is now created
        @test !isnothing(julia_ctx.jl_pkg_index)
        @test julia_ctx.jl_pkg_index isa Task

        # Process another query - should use existing index
        prev_index = julia_ctx.jl_pkg_index
        result2 = process_julia_context(julia_ctx, "How to use strings?")

        # Verify same index is used
        @test julia_ctx.jl_pkg_index === prev_index
    end
end
;