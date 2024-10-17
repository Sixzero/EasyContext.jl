using Test
using EasyContext
using EasyContext: QuestionCTX

@testset "QuestionCTX Tests" begin
    @testset "Basic functionality" begin
        qa = QuestionCTX()
        
        # Test single question
        result = qa("First question")
        @test occursin("1. First question", result)
        @test occursin("<UserQuestion>", result)
        @test !occursin("<PastUserQuestions>", result)

        # Test two questions
        result = qa("Second question")
        @test occursin("1. First question", result)
        @test occursin("2. Second question", result)
        @test occursin("<PastUserQuestions>", result)
        @test occursin("<UserQuestion>", result)
    end

    @testset "Max questions limit" begin
        qa = QuestionCTX(max_questions=3)
        
        qa("Question 1")
        qa("Question 2")
        qa("Question 3")
        result = qa("Question 4")

        @test occursin("1. Question 2", result)
        @test occursin("2. Question 3", result)
        @test occursin("3. Question 4", result)
        @test !occursin("Question 1", result)
    end

    @testset "Empty initial state" begin
        qa = QuestionCTX()
        @test isempty(qa.questions)
        @test qa.max_questions == 5  # default value
    end
end
;
