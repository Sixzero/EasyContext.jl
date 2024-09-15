using PromptingTools.Experimental.RAGTools: RAGContext, SourceChunk

mutable struct QuestionAccumulator
    questions::Vector{String}
    max_questions::Int

    QuestionAccumulator(max_questions::Int = 5) = new(String[], max_questions)
end

function (qa::QuestionAccumulator)(question::String)
    push!(qa.questions, question)
    if length(qa.questions) > qa.max_questions
        popfirst!(qa.questions)
    end
    
    if length(qa.questions) > 1
        history = join(qa.questions[1:end-1], "\n")
        return """
        <PastQuestions>
        $history
        </PastQuestions>

        <CurrentQuestion>
        $(qa.questions[end])
        </CurrentQuestion>
        """
    else
        return """
        <CurrentQuestion>
        $(qa.questions[end])
        </CurrentQuestion>
        """
    end
end

