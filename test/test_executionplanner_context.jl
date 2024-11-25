using Test
using EasyContext
using PromptingTools: AIMessage
using Dates

@testset "ExecutionPlannerContext Tests" begin
    @testset "Basic functionality" begin
        planner = ExecutionPlannerContext(model="gem15f")
        
        # Test with session
        session = initSession(sys_msg="Test planning session")
        # Add some history
        session(create_user_message("Let's implement a sorting algorithm"))
        session(create_AI_message("First, we need to define the interface"))
        session(create_user_message("We should consider performance"))
        session(create_AI_message("Let's look at the standard library"))
        session(create_user_message("We can use Base.sort!"))
        
        # Test with default history count (3)
        result = planner(session, "How to implement QuickSort?")
        @test result isa AbstractString
        @test !isempty(result)
        
        # Test with custom history count
        result = planner(session, "How to implement QuickSort?"; history_count=5)
        @test result isa AbstractString
        @test !isempty(result)
        
        # Test with custom history count in constructor
        planner_with_more_history = ExecutionPlannerContext(model="gem15f", history_count=5)
        result = planner_with_more_history(session, "How to implement QuickSort?")
        @test result isa AbstractString
        @test !isempty(result)
    end
    
end