using PromptingTools: SystemMessage, UserMessage
using Markdown

export ExecutionPlannerContext, LLM_ExecutionPlanner

Base.@kwdef mutable struct ExecutionPlannerContext
    enabled::Bool = true
    model::String = "dscode"
    temperature::Float64 = 0.8
    top_p::Float64 = 0.8
    history_count::Int = 3
end

transform_position(::Type{ExecutionPlannerContext}) = AppendTransform()

Base.display(ctx::ExecutionPlannerContext, content::AbstractString) = 
    display(Markdown.parse("# EXECUTION_PLAN\n" * content))

function transform(ctx::ExecutionPlannerContext, query, session::Session, io::IO=stdout)
    !ctx.enabled && return ""
    history_len = ctx.history_count
    relevant_history = join([msg.content for msg in session.messages[max(1, end-history_len+1):end]], "\n")
    
    prompt = """
    PREVIOUS_CONTEXT
    $relevant_history
    /PREVIOUS_CONTEXT

    USER_QUESTION
    $query
    /USER_QUESTION

    Based on the above PREVIOUS_CONTEXT USER_QUESTION, create a detailed execution plan, which is sufficient to answer user question.
    """
    
    cb = create(StreamCallbackConfig(highlight_enabled=true, process_enabled=false; io))

    response = aigenerate([
        SystemMessage(PLANNER_SYSTEM_PROMPT),
        UserMessage(prompt)
    ], model=ctx.model, api_kwargs=(temperature=ctx.temperature, top_p=ctx.top_p), streamcallback=cb)
    
    content = response.content
    display(ctx, content)
    "\n\n<EXECUTION_PLAN>\n" * content * "\n</EXECUTION_PLAN>\n\n"
end

const PLANNER_SYSTEM_PROMPT = """
You are an expert project planner who creates clear, actionable plans. Break down complex tasks while considering context, risks, and resources.

For each request:
1. Understand context and requirements
2. Identify risks and dependencies
3. Create clear action steps
4. Define success criteria
5. Add confidence level [Confident|Probable|Uncertain|Speculative] after each suggestion

Format responses using:

# Project Goal
[Clear outcome statement]

# Context Analysis
- Requirements and constraints
- Available resources
- Key stakeholders

# Action Plan
1. [Step name]
   - Actions and timeline [Confidence]
   - Required resources [Confidence]
   - Dependencies [Confidence]

# Success Criteria
- Measurable outcomes [Confidence]
- Validation methods [Confidence]
- Key checkpoints [Confidence]

Remember to:
- Be specific and actionable
- Flag potential risks
- Consider resource constraints
- Propose alternatives when needed
"""

