using PromptingTools: SystemMessage, UserMessage
using Markdown

export ExecutionPlannerContext, LLM_ExecutionPlanner

Base.@kwdef mutable struct ExecutionPlannerContext <: AbstractPlanner
    enabled::Bool = true
    model::String = "dscode"
    temperature::Float64 = 0.8
    top_p::Float64 = 0.8
    history_count::Int = 3
end

transform_position(::Type{ExecutionPlannerContext}) = AppendTransform()

Base.display(ctx::ExecutionPlannerContext, content::AbstractString) = 
    display(Markdown.parse("# EXECUTION_PLAN\n" * content))

function transform(ctx::ExecutionPlannerContext, query, session::Session; io::IO=stdout)
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
    StreamCallbackTYPE= pickStreamCallbackforIO(io)
    cb = create(StreamCallbackTYPE(highlight_enabled=true, process_enabled=false; io, mode="EXECUTION_PLAN"))

    api_kwargs = (; temperature=ctx.temperature, top_p=ctx.top_p)
    if ctx.model == "o3m" # NOTE: o3m does not support temperature and top_p
        api_kwargs = (; )
    end
    response = aigenerate([
        SystemMessage(PLANNER_SYSTEM_PROMPT),
        UserMessage(prompt)
    ], model=ctx.model, api_kwargs=api_kwargs, http_kwargs=(; readtimeout=300), streamcallback=cb)
    
    content = response.content
    display(ctx, content)
    "\n\n<EXECUTION_PLAN>\n" * content * "\n</EXECUTION_PLAN>\n\n"
end

const PLANNER_SYSTEM_PROMPT = """
You are an expert project planner who creates clear, actionable plans. Break down complex tasks while considering context, risks, and resources.

For each request:
1. Understand context and requirements
2. Create clear action steps
3. Define success criteria
4. Add confidence level [Confident|Probable|Uncertain|Speculative] after each suggestion, where you feel the need

Format responses using:

# Project Goal
[Clear outcome statement]

# Context Analysis
- Requirements and constraints

# Solution Plan
1. [Step name]
   - Description and timeline [Confidence]
   - Solution ideas, codesnippets
   - Dependencies, required resources (optional)

# Solution Plan B (optional)
   Simple plan with optional snippet examples

# Success Criteria
- Key checkpoints [Confidence]

Remember to:
- Be specific and actionable
- Flag potential risks or signal confidence
- Propose multiple alternatives if needed
- Be concise
"""

