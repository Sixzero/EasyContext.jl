using Test
using BenchmarkTools
using EasyContext

@testset "Julia Context Performance Tests" begin
    @testset "init_julia_context performance" begin
        # Benchmark the initialization of Julia context
        b = @benchmarkable init_julia_context()
        result = run(b, samples=5, seconds=10)
        
        @test median(result.times) < 1e9  # Assert that median time is less than 1 second
        @test maximum(result.times) < 2e9  # Assert that maximum time is less than 2 seconds
        
        println("init_julia_context performance:")
        show(stdout, MIME("text/plain"), result)
        println("\n")
    end

    @testset "process_julia_context performance" begin
        # Initialize context once for all process_julia_context tests
        julia_context = init_julia_context(verbose=false)
        
        # Test with a short question
        short_question = "How to use arrays in Julia?"
        b_short = @benchmarkable process_julia_context($julia_context, $short_question)
        result_short = run(b_short, samples=5, seconds=10)
        
        @test median(result_short.times) < 500e6  # Assert that median time is less than 500 ms
        @test maximum(result_short.times) < 1e9  # Assert that maximum time is less than 1 second
        
        println("process_julia_context performance (short question):")
        show(stdout, MIME("text/plain"), result_short)
        println("\n")

        # Test with a longer, more complex question
        long_question = "Explain the differences between multiple dispatch and single dispatch, and provide examples of how Julia's multiple dispatch system can be used to write efficient and extensible code."
        b_long = @benchmarkable process_julia_context($julia_context, $long_question)
        result_long = run(b_long, samples=5, seconds=10)
        
        @test median(result_long.times) < 1e9  # Assert that median time is less than 1 second
        @test maximum(result_long.times) < 2e9  # Assert that maximum time is less than 2 seconds
        
        println("process_julia_context performance (long question):")
        show(stdout, MIME("text/plain"), result_long)
        println("\n")
    end
end
;