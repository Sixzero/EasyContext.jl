
@kwdef mutable struct QuestionCTX
    questions::Vector{String}=String[]
    max_questions::Int=4
end

function (qa::QuestionCTX)(question::String)
    push!(qa.questions, question)
    length(qa.questions) > qa.max_questions && popfirst!(qa.questions)
    
    if length(qa.questions) > 1
        history = join(["$i. $msg" for (i, msg) in enumerate(qa.questions[1:end-1])], "\n")
        return """
        <PastQuestions>
        $history
        </PastQuestions>
        <CurrentQuestion>
        $(length(qa.questions)). $(qa.questions[end])
        </CurrentQuestion>
        """
    else
        return """
        <CurrentQuestion>
        1. $(qa.questions[end])
        </CurrentQuestion>
        """
    end
end

