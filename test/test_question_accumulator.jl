using Test
using EasyContext
using EasyContext: QueryWithHistory, format_history_query

@testset "QueryWithHistory Tests" begin
    @testset "Basic functionality" begin
        qa = QueryWithHistory()
        
        # Test single question
        history, current = qa("First question")
        @test isempty(history)
        @test current == "First question"
        
        # Test formatted output
        result = format_history_query((history, current))
        @test occursin("User query:", result)
        @test occursin("First question", result)

        # Test two questions
        history, current = qa("Second question")
        @test occursin("1. First question", history)
        @test current == "Second question"
        
        result = format_history_query((history, current))
        @test occursin("User query history:", result)
        @test occursin("Latest user query:", result)
    end

    @testset "Max questions limit" begin
        qa = QueryWithHistory(max_questions=3)
        
        qa("Question 1")
        qa("Question 2")
        qa("Question 3")
        history, current = qa("Question 4")

        @test occursin("2. Question 2", history)
        @test occursin("3. Question 3", history)
        @test current == "Question 4"
        @test !occursin("Question 1", history)
    end

    @testset "Empty initial state" begin
        qa = QueryWithHistory()
        @test isempty(qa.questions)
        @test qa.max_questions == 3  # default value
    end
end

@testset "ConversationCTX Tests" begin
    @testset "Basic conversation" begin
        conv = ConversationCTX()
        
        result = conv("What is Julia?")
        @test occursin("Latest message:\nWhat is Julia?", result)
        
        add_response!(conv, "Julia is a programming language.")
        result = conv("Is it fast?")
        @test occursin("Human: What is Julia?", result)
        @test occursin("Assistant: Julia is a programming language.", result)
        
        add_response!(conv, "Yes, very fast!")
        result = conv("Can I use it for AI?")
        @test occursin("Conversation history:", result)
        @test occursin("Human: Is it fast?", result)
        @test occursin("Assistant: Yes, very fast!", result)
    end

    @testset "Message limits" begin
        conv = ConversationCTX()
        conv("M1")
        add_response!(conv, "R1")
        conv("M2")
        add_response!(conv, "R2")
        conv("M3")
        result = conv("M4")
        
        @test !occursin("M1", result)
        @test occursin("M2", result)
        @test occursin("M3", result)
        @test occursin("M4", result)
        @test occursin("R2", result)
    end
end
;
