using PromptingTools: SystemMessage, UserMessage

export ExecutionPlannerContext

Base.@kwdef mutable struct ExecutionPlannerContext
    model::String = "oro1"
    temperature::Float64 = 0.8
    top_p::Float64 = 0.8
    history_count::Int = 3
end

const PLANNER_SYSTEM_PROMPT = """
You are an expert project planner who creates clear, actionable, and efficient plans.
Break down complex tasks into manageable steps, considering:
1. Dependencies and prerequisites
2. Potential challenges and solutions
3. Resource requirements
4. Optimal sequence of actions
5. Success criteria and validation steps
6. Point out if something is missused

Format your response in markdown with clear sections:
# Goal
# Context Analysis
# Step-by-Step Plan
# Success Criteria
"""

function (ctx::ExecutionPlannerContext)(session::Session, user_question::AbstractString; history_count::Union{Int,Nothing}=nothing)
    history_len = something(history_count, ctx.history_count)
    relevant_history = join([msg.content for msg in session.messages[max(1, end-history_len+1):end]], "\n")
    
    prompt = """
    PREVIOUS_CONTEXT
    $relevant_history
    /PREVIOUS_CONTEXT

    USER_QUESTION
    $user_question
    /USER_QUESTION

    Based on the above PREVIOUS_CONTEXT USER_QUESTION, create a detailed execution plan, which is sufficient to answer user question.
    """
    conversation = [
        SystemMessage(PLANNER_SYSTEM_PROMPT),
        UserMessage(prompt)
    ]
    response = aigenerate(conversation,
        model=ctx.model,
        api_kwargs=(temperature=ctx.temperature, top_p=ctx.top_p)
    )
    
    return response.content
end

