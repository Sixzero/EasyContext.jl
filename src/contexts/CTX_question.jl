@kwdef mutable struct QueryWithHistory
    questions::Vector{String}=String[]
    max_questions::Int=3
end

function (qa::QueryWithHistory)(query::AbstractString)
    push!(qa.questions, query)
    length(qa.questions) > qa.max_questions && popfirst!(qa.questions)
    
    history = length(qa.questions) > 1 ? join(["$i. $msg" for (i, msg) in enumerate(qa.questions[1:end-1])], "\n") : ""
    
    return (history, query)
end

function format_history_query((history, query)::Tuple{<:AbstractString,<:AbstractString}, extra_contexts::Vector{Pair{String,String}}=Pair{String,String}[], latest_user_query_title="Latest user query:")
    parts = String[]
    
    # Past user queries first
    !isempty(history) && push!(parts, """User query history:\n$history""")
    
    # Extra contexts in the middle
    for (title, content) in extra_contexts
        !isempty(content) && push!(parts, """$title\n$content""")
    end
    
    # Current query last
    push!(parts, """$(latest_user_query_title)\n$query""")
    
    join(parts, "\n\n")
end

@kwdef mutable struct QueryWithHistoryAndAIMsg
    question_history::QueryWithHistory=QueryWithHistory()
    max_assistant::Int=1
end

function (conv::QueryWithHistoryAndAIMsg)(query::AbstractString, session::Session, ctx_shell::AbstractString="")
    # Get AI history first
    ai_history = String[]
    for msg in reverse(session.messages)
        if msg.role == :assistant && length(ai_history) < conv.max_assistant
            pushfirst!(ai_history, msg.content)
        end
    end
    
    # Build extra contexts
    contexts = Pair{String,String}[]
    !isempty(ai_history) && push!(contexts, "AI responses:" => join(ai_history, "\n"))
    !isempty(ctx_shell) && push!(contexts, "Shell context:" => ctx_shell)
    
    # Format with all parts in order
    format_history_query(conv.question_history(query), contexts, "CURRENT QUERY TO SOLVE:")
end

add_response!(conv::QueryWithHistoryAndAIMsg, response::AbstractString) = 
    push!(conv.messages, create_AI_message(response))