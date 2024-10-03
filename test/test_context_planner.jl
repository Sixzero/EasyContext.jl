using Test
using EasyContext
using PromptingTools

@testset "Context Planner Tests" begin
    @testset "llm_context_planner functionality" begin
        ctx_question = "How do I use DifferentialEquations.jl to solve an ODE?"
        tools = [
            (:julia_context, "Provides context about Julia packages and functions", nothing),
            (:google_search, "Performs a Google search for information", nothing),
            (:codebase_context, "Provides context from the current codebase", nothing)
        ]

        result = llm_context_planner(ctx_question, tools)

        @test isa(result, Vector{String})
        @test !isempty(result)
        @test all(tool -> tool in string.(first.(tools)), result)
    end

    @testset "llm_context_planner with custom model" begin
        ctx_question = "What is the syntax for using the solve function in DifferentialEquations.jl?"
        tools = [
            (:julia_context, "Provides context about Julia packages and functions", nothing),
            (:google_search, "Performs a Google search for information", nothing)
        ]

        result = llm_context_planner(ctx_question, tools; model="gpt4t")

        @test isa(result, Vector{String})
        @test !isempty(result)
        @test all(tool -> tool in string.(first.(tools)), result)
    end

    @testset "Integration with real tools" begin
        ctx_question = "What is the syntax for using the solve function in DifferentialEquations.jl?"
        julia_context = (ctx) -> "Julia context provided"
        google_search = (query) -> "Google search results for: $query"

        tools = [
            (:julia_context, "Provides context about Julia packages and functions", julia_context),
            (:google_search, "Performs a Google search for information", google_search)
        ]

        selected_tools = llm_context_planner(ctx_question, tools)

        @test isa(selected_tools, Vector{String})
        @test !isempty(selected_tools)
        @test all(tool -> tool in string.(first.(tools)), selected_tools)

        # Simulate using the selected tools
        for tool in selected_tools
            tool_func = last(filter(t -> string(t[1]) == tool, tools)[1])
            result = tool_func(ctx_question)
            @test !isempty(result)
        end
    end
end
