# PlanTool - Sub-agent generator for implementation planning
#
# A ToolGenerator that holds sub-tools. When the LLM calls "plan" with a query,
# it spawns a read-only FluidAgent to design an implementation plan.

export PlanTool

const PLAN_TAG = "plan"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct PlanToolCall <: ToolCallFormat.AbstractTool
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

ToolCallFormat.get_id(t::PlanToolCall) = t._id
ToolCallFormat.toolname(::Type{PlanToolCall}) = PLAN_TAG
LLM_safetorun(::PlanToolCall) = true

const PLAN_SYS_PROMPT = """You are a planning agent. Design detailed implementation plans by exploring the codebase first, then proposing a decision-complete plan.

$(codex_plan_mode_prompt)

$(opencode_gemini_understand_prompt)

IMPORTANT: Do NOT modify any files. Only read, inspect, and plan."""

function ToolCallFormat.execute(cmd::PlanToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    ext_type = something(cmd.extractor_type, tools -> NativeExtractor(tools; no_confirm=true))
    raw_io = cmd.extractor_type !== nothing ? ctx : devnull
    io = subagent_io(raw_io, string(cmd._id))
    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = ext_type,
        sys_msg = PLAN_SYS_PROMPT,
    )
    response = work(agent, cmd.prompt; io=io, quiet=true, on_meta_ai=on_meta_ai(cmd.stats),
        tool_kwargs=Dict(:ctx => ctx))
    cmd.process_result = ProcessResult(response !== nothing ? something(response.content, "(no response)") : "(no response)")
    cmd
end


# --- The generator (holds config, handed to agent at setup) ---
@kwdef struct PlanTool <: AbstractToolGenerator
    tools::Vector
    model::Union{String, Nothing} = nothing
    extractor_type::Union{Function, Nothing} = nothing
end

ToolCallFormat.toolname(::PlanTool) = PLAN_TAG

const PLAN_SCHEMA = (
    name = PLAN_TAG,
    description = "Launch a planning sub-agent to design an implementation approach. The agent explores the codebase and returns a detailed, decision-complete plan.",
    params = [
        (name = "prompt", type = "string", description = "The planning task: what needs to be designed or implemented", required = true),
        (name = "timeout", type = "integer", description = "Timeout in seconds for the sub-agent (default: 300)", required = false, default = 300),
    ]
)

ToolCallFormat.get_tool_schema(::PlanTool) = PLAN_SCHEMA
ToolCallFormat.get_tool_schema(::Type{PlanToolCall}) = PLAN_SCHEMA
ToolCallFormat.get_description(::PlanTool) = description_from_schema(PLAN_SCHEMA)

function ToolCallFormat.create_tool(pt::PlanTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    timeout_pv = get(call.kwargs, "timeout", nothing)
    timeout = timeout_pv !== nothing ? Int(timeout_pv.value) : 300
    PlanToolCall(; prompt, timeout, tools=pt.tools, model=pt.model, extractor_type=pt.extractor_type)
end
