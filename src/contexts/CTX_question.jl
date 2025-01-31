export QueryWithHistory, QueryWithHistoryAndAIMsg

@kwdef mutable struct QueryWithHistory
    questions::Vector{String}=String[]
    max_questions::Int=3
end

function get_context!(qa::QueryWithHistory, query::AbstractString)
    @assert isempty(qa.questions) || (!isempty(qa.questions) && last(qa.questions) != query) "Query already in history"
    push!(qa.questions, query)
    length(qa.questions) > qa.max_questions && popfirst!(qa.questions)
    
    history = length(qa.questions) > 1 ? join(["$i. $msg" for (i, msg) in enumerate(qa.questions[1:end-1])], "\n") : ""
    
    return history
end

function format_history_query(qa::QueryWithHistory, query, extra_contexts::Vector{Pair{String,String}}=Pair{String,String}[], latest_user_query_title="Latest user query:")
    parts = String[]
    history = get_context!(qa, query)
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
    query_history::QueryWithHistory=QueryWithHistory()
    max_assistant::Int=1
end

function get_context!(conv::QueryWithHistoryAndAIMsg, query::AbstractString, session::Session, ctx_shell::AbstractString="")
    # Get AI history first
    ai_history = String[]
    for msg in reverse(session.messages)
        if msg.role == :assistant && length(ai_history) < conv.max_assistant
            pushfirst!(ai_history, msg.content)
        end
    end
    
    # Build extra contexts
    contexts = Pair{String,String}[]
    !isempty(ai_history) && push!(contexts, "# AI responses:" => join(ai_history, "\n"))
    !isempty(ctx_shell) && push!(contexts, "# Previous tools and their results:" => ctx_shell)
    
    # Format with all parts in order
    format_history_query(conv.query_history, query, contexts, "# Current query to solve:")
end

add_response!(conv::QueryWithHistoryAndAIMsg, response::AbstractString) = 
    push!(conv.messages, create_AI_message(response))