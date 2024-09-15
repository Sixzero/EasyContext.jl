
@kwdef mutable struct QuestionAccumulatorProcessor
    questions::Vector{String}=String[]
    max_questions::Int=5
end

function (qa::QuestionAccumulatorProcessor)(question::String)
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

