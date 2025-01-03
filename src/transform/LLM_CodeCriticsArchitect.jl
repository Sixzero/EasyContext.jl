# ./src/transform/LLM_CodeCriticsArchitect.jl
using PromptingTools: SystemMessage, UserMessage
using Markdown
using StreamCallbacksExt
using StreamCallbacksExt: format_ai_message, format_user_message

export CodeCriticsArchitectContext, LLM_CodeCriticsArchitect

@kwdef mutable struct CodeCriticsArchitectContext
    enabled::Bool = true
    model::String = "dscode"
    temperature::Float64 = 0.7
    top_p::Float64 = 0.8
    history_count::Int = 2
end

transform_position(::Type{CodeCriticsArchitectContext}) = AppendTransform()

Base.display(ctx::CodeCriticsArchitectContext, content::AbstractString) = 
    display(Markdown.parse("# CODE_CRITICS\n" * content))

function transform(ctx::CodeCriticsArchitectContext, query, session::Session)
    !ctx.enabled && return ""
    history_len = ctx.history_count
    relevant_history = join([msg.content for msg in session.messages[max(1, end-history_len+1):end]], "\n")
    
    prompt = """
    CONTEXT
    $relevant_history
    /CONTEXT

    CURRENT_QUESTION
    $query
    /CURRENT_QUESTION

    Review the code/solution above and provide concise, actionable feedback focusing on:
    1. Potential issues or bugs
    2. Simple improvement suggestions
    3. Critical fixes needed
    Be minimal, focus only on important issues.
    """
    
    cb = create(StreamCallbackConfig(highlight_enabled=true, process_enabled=false))

    response = aigenerate([
        SystemMessage(CRITICS_SYSTEM_PROMPT),
        UserMessage(prompt)
    ], model=ctx.model, api_kwargs=(temperature=ctx.temperature, top_p=ctx.top_p), streamcallback=cb)
    
    content = response.content
    display(ctx, content)
    "\n\n<CODE_CRITICS>\n" * content * "\n</CODE_CRITICS>\n\n"
end

const CRITICS_SYSTEM_PROMPT = """
You are a code review expert focused on identifying critical issues and suggesting practical improvements.

Guidelines:
- Focus on significant issues only
- Provide specific, actionable feedback
- Keep suggestions minimal and practical
- Ignore minor style issues unless critical
- Consider performance and reliability
- Add confidence level [Confident|Probable|Uncertain|Speculative] after each suggestion

Format response as:

# Critical Issues
- [Issue]: [Quick fix suggestion] [Confidence]

# Improvements
- [Area]: [Concise improvement idea] [Confidence]

Keep responses short and focused on what matters most.
"""
