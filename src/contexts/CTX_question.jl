export QueryWithHistory, QueryWithHistoryAndAIMsg

@kwdef mutable struct QueryWithHistory
    questions::Vector{String}=String[]
    max_questions::Int=3
end

# Pure: returns history string (excluding the latest query)
function get_history(qa::QueryWithHistory)
    history = length(qa.questions) > 1 ? join(["$i. $msg" for (i, msg) in enumerate(qa.questions[1:end-1])], "\n") : ""
    return history
end

# Mutating: only updates the stored history
function update_history!(qa::QueryWithHistory, query::AbstractString)
    if isempty(qa.questions) || (!isempty(qa.questions) && last(qa.questions) != query)
        push!(qa.questions, query)
        length(qa.questions) > qa.max_questions && popfirst!(qa.questions)
    else
        @info("This query got repeated, so we didn't add it to the history.")
    end
    return qa
end

# Legacy-compatible: keeps name but delegates to the new split functions
function get_context!(qa::QueryWithHistory, query::AbstractString)
    update_history!(qa, query)
    return get_history(qa)
end

# Pure formatter: formats a history + extras + current query into a prompt
function format_query_context(history::AbstractString, query, extra_contexts::Vector{Pair{String,String}}=Pair{String,String}[], latest_user_query_title="Latest user query:")
    parts = String[]
    for (title, content) in extra_contexts
        !isempty(content) && push!(parts, """$title\n$content""")
    end
    !isempty(history) && push!(parts, """User query history:\n$history""")
    push!(parts, """$(latest_user_query_title)\n$query""")
    return join(parts, "\n\n")
end

# Thin wrapper: preserves old call shape but no mutation/reading inside formatter
function format_history_query(qa::QueryWithHistory, query, extra_contexts::Vector{Pair{String,String}}=Pair{String,String}[], latest_user_query_title="Latest user query:")
    return format_query_context(get_history(qa), query, extra_contexts, latest_user_query_title)
end

@kwdef mutable struct QueryWithHistoryAndAIMsg
    query_history::QueryWithHistory=QueryWithHistory()
    max_assistant::Int=1
end

# Pure: history getter for the composite type (as requested)
get_history(conv::QueryWithHistoryAndAIMsg) = get_history(conv.query_history)

# Mutating: update user history through the composite type
function update_history!(conv::QueryWithHistoryAndAIMsg, query::AbstractString)
    update_history!(conv.query_history, query)
    return conv
end

# Pure: extract last N assistant messages (oldest->newest)
function get_ai_history(session::Session, max_assistant::Int)
    ai_history = String[]
    for msg in reverse(session.messages)
        if msg.role == :assistant
            pushfirst!(ai_history, msg.content)
            length(ai_history) >= max_assistant && break
        end
    end
    return join(ai_history, "\n")
end

function get_context!(conv::QueryWithHistoryAndAIMsg, query::AbstractString, session::Session, ctx_shell::AbstractString="")
    # 1) mutate only the user history
    update_history!(conv, query)

    # 2) gather pure contexts
    ai_history = get_ai_history(session, conv.max_assistant)
    contexts = Pair{String,String}[]
    !isempty(ai_history) && push!(contexts, "# AI responses:" => ai_history)
    !isempty(ctx_shell) && push!(contexts, "# Previous tools and their results:" => ctx_shell)

    # 3) format purely from data
    return format_query_context(get_history(conv), query, contexts, "# Current query to solve:")
end

add_response!(conv::QueryWithHistoryAndAIMsg, response::AbstractString) = 
    push!(conv.messages, create_AI_message(response))