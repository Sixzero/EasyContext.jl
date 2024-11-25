
@kwdef mutable struct QuestionCTX
    questions::Vector{String}=String[]
    max_questions::Int=4
end

function (qa::QuestionCTX)(question::AbstractString)
    push!(qa.questions, question)
    length(qa.questions) > qa.max_questions && popfirst!(qa.questions)
    
    if length(qa.questions) > 1
        history = join(["$i. $msg" for (i, msg) in enumerate(qa.questions[1:end-1])], "\n")
        return """
        <PastUserQuestions>
        $history
        </PastUserQuestions>
        <UserQuestion>
        $(length(qa.questions)). $(qa.questions[end])
        </UserQuestion>
        """
    else
        return """
        <UserQuestion>
        $(qa.questions[end])
        </UserQuestion>
        """
    end
end

