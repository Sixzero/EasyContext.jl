using Test
using EasyContext
using EasyContext: QuestionAccumulatorProcessor

@testset "QuestionAccumulatorProcessor Tests" begin
    @testset "Basic functionality" begin
        qa = QuestionAccumulatorProcessor()
        
        # Test single question
        result = qa("First question")
        @test occursin("1. First question", result)
        @test occursin("<CurrentQuestion>", result)
        @test !occursin("<PastQuestions>", result)

        # Test two questions
        result = qa("Second question")
        @test occursin("1. First question", result)
        @test occursin("2. Second question", result)
        @test occursin("<PastQuestions>", result)
        @test occursin("<CurrentQuestion>", result)
    end

    @testset "Max questions limit" begin
        qa = QuestionAccumulatorProcessor(max_questions=3)
        
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
        qa = QuestionAccumulatorProcessor()
        @test isempty(qa.questions)
        @test qa.max_questions == 5  # default value
    end
end
;
