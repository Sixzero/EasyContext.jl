using PromptingTools: SystemMessage, UserMessage

export ExecutionPlannerContext, LLM_ExecutionPlanner

Base.@kwdef mutable struct ExecutionPlannerContext
    model::String = "oro1"
    temperature::Float64 = 0.8
    top_p::Float64 = 0.8
    history_count::Int = 3
end

const PLANNER_SYSTEM_PROMPT = """
You are an expert project planner who creates clear, actionable plans. Break down complex tasks while considering context, risks, and resources.

For each request:
1. Understand context and requirements
2. Identify risks and dependencies
3. Create clear action steps
4. Define success criteria

Format responses using:

# Project Goal
[Clear outcome statement]

# Context Analysis
- Requirements and constraints
- Available resources
- Key stakeholders

# Action Plan
1. [Step name]
   - Actions and timeline
   - Required resources
   - Dependencies

# Success Criteria
- Measurable outcomes
- Validation methods
- Key checkpoints

Remember to:
- Be specific and actionable
- Flag potential risks
- Consider resource constraints
- Propose alternatives when needed
"""
 
LLM_ExecutionPlanner(ctx::ExecutionPlannerContext, session::Session, user_question::AbstractString; history_count::Union{Int,Nothing}=nothing) = begin
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

