# PlanTool - Sub-agent generator for implementation planning
#
# A ToolGenerator that holds sub-tools. When the LLM calls "plan" with a query,
# it spawns a read-only FluidAgent to design an implementation plan.

export PlanTool

const PLAN_TAG = "plan"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct PlanToolCall <: ToolCallFormat.AbstractTool
    _id::UUID = uuid4()
    query::String
    tools::Vector
    model::Union{String, Nothing}
end

ToolCallFormat.get_id(t::PlanToolCall) = t._id
LLM_safetorun(::PlanToolCall) = true

const _plan_results = Dict{UUID, String}()

const PLAN_SYS_PROMPT = """You are a planning agent. Design detailed implementation plans by exploring the codebase first, then proposing a decision-complete plan.

$(codex_plan_mode_prompt)

$(opencode_gemini_understand_prompt)

IMPORTANT: Do NOT modify any files. Only read, inspect, and plan."""

function ToolCallFormat.execute(cmd::PlanToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = PLAN_SYS_PROMPT,
    )
    agent.tool_mode = :native

    response = work(agent, cmd.query; io=devnull, quiet=true)
    content = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    _plan_results[cmd._id] = content
    cmd
end

ToolCallFormat.result2string(cmd::PlanToolCall) = pop!(_plan_results, cmd._id, "(no result)")

# --- The generator (holds config, handed to agent at setup) ---
@kwdef struct PlanTool <: AbstractToolGenerator
    tools::Vector
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::PlanTool) = PLAN_TAG

const PLAN_SCHEMA = (
    name = PLAN_TAG,
    description = "Launch a planning sub-agent to design an implementation approach. The agent explores the codebase and returns a detailed, decision-complete plan.",
    params = [
        (name = "query", type = "string", description = "The planning task: what needs to be designed or implemented", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::PlanTool) = PLAN_SCHEMA
ToolCallFormat.get_description(::PlanTool) = description_from_schema(PLAN_SCHEMA)

function ToolCallFormat.create_tool(pt::PlanTool, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    PlanToolCall(; query, tools=pt.tools, model=pt.model)
end
