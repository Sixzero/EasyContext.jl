# ReviewTool - Sub-agent generator for code review
#
# A ToolGenerator that holds sub-tools. When the LLM calls "review" with a prompt,
# it spawns a read-only FluidAgent, reviews changes against the goal, returns findings.

export ReviewTool

const REVIEW_TAG = "review"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct ReviewToolCall <: ToolCallFormat.AbstractTool
    _id::UUID = uuid4()
    _tool_call_id::Union{String, Nothing} = nothing
    prompt::String
    tools::Vector
    model::Union{String, Nothing}
    extractor_type::Union{Function, Nothing} = nothing
    timeout::Union{Int, Nothing} = 300
    stats::SubAgentStats = SubAgentStats()
    process_result::Union{ProcessResult, Nothing} = nothing
end

ToolCallFormat.get_id(t::ReviewToolCall) = t._id
ToolCallFormat.toolname(::Type{ReviewToolCall}) = REVIEW_TAG
LLM_safetorun(::ReviewToolCall) = true

const REVIEW_SYS_PROMPT = """You are a review and advisory agent. Your job is to evaluate whether the original goal was accomplished optimally.

Use git diff, git status, read files, and search to understand what was done. Then:
- Assess whether the goal was fully and correctly achieved
- Identify issues, bugs, or missing pieces
- Suggest simpler or cleaner approaches that could achieve the same goal
- Propose alternative solutions or architectural improvements
- Question whether the approach taken was the best path

$(opencode_gemini_understand_prompt)

IMPORTANT: Do NOT modify any files. Only read, inspect, and report findings.
If a tool fails 3 times, stop retrying and report that the tools are faulty."""

function ToolCallFormat.execute(cmd::ReviewToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "openai:openai/gpt-5.5")

    ext_type = something(cmd.extractor_type, tools -> NativeExtractor(tools; no_confirm=true))
    raw_io = cmd.extractor_type !== nothing ? ctx : devnull
    io = subagent_io(raw_io, string(cmd._id))
    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = ext_type,
        sys_msg = REVIEW_SYS_PROMPT,
    )
    response = work(agent, cmd.prompt; io=io, quiet=true, on_meta_ai=on_meta_ai(cmd.stats),
        tool_kwargs=Dict(:ctx => ctx))
    cmd.process_result = ProcessResult(response !== nothing ? something(response.content, "(no response)") : "(no response)")
    cmd
end


# --- The generator (holds config, handed to agent at setup) ---
@kwdef struct ReviewTool <: AbstractToolGenerator
    tools::Vector
    model::Union{String, Nothing} = nothing
    extractor_type::Union{Function, Nothing} = nothing
end

ToolCallFormat.toolname(::ReviewTool) = REVIEW_TAG

const REVIEW_SCHEMA = (
    name = REVIEW_TAG,
    description = "Launch a read-only sub-agent to evaluate whether a goal was accomplished optimally. Reviews changes, suggests simplifications, proposes alternative approaches, and identifies issues.",
    params = [
        (name = "prompt", type = "string", description = "The review task: include the original goal, context, and what to review", required = true),
        (name = "timeout", type = "integer", description = "Timeout in seconds for the sub-agent (default: 300)", required = false, default = 300),
    ]
)

ToolCallFormat.get_tool_schema(::ReviewTool) = REVIEW_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ReviewToolCall}) = REVIEW_SCHEMA
ToolCallFormat.get_description(::ReviewTool) = description_from_schema(REVIEW_SCHEMA)

function ToolCallFormat.create_tool(rt::ReviewTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    timeout_pv = get(call.kwargs, "timeout", nothing)
    timeout = timeout_pv !== nothing ? Int(timeout_pv.value) : 300
    ReviewToolCall(; prompt, timeout, tools=rt.tools, model=rt.model, extractor_type=rt.extractor_type)
end
