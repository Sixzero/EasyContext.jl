# ExploreTool - Sub-agent generator for codebase exploration
#
# A ToolGenerator that holds sub-tools. When the LLM calls "explore" with a query,
# it spawns a read-only FluidAgent, runs the query, returns the final summary.

export ExploreTool

const EXPLORE_TAG = "explore"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct ExploreToolCall <: ToolCallFormat.AbstractTool
    _id::UUID = uuid4()
    _tool_call_id::Union{String, Nothing} = nothing
    query::String
    tools::Vector
    model::Union{String, Nothing}
    stats::SubAgentStats = SubAgentStats()
    result::Union{String, Nothing} = nothing
end

ToolCallFormat.get_id(t::ExploreToolCall) = t._id
ToolCallFormat.toolname(::Type{ExploreToolCall}) = EXPLORE_TAG
LLM_safetorun(::ExploreToolCall) = true

const EXPLORE_SYS_PROMPT = """You are a codebase exploration agent. Read files, run non-destructive shell commands (ls, grep, find, tree), and report findings.

$(opencode_gemini_understand_prompt)

IMPORTANT: Do NOT modify any files. Only read and inspect.
If a tool fails 3 times, stop retrying and report that the tools are faulty."""

function ToolCallFormat.execute(cmd::ExploreToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = EXPLORE_SYS_PROMPT,
    )
    response = work(agent, cmd.query; io=devnull, quiet=true, on_meta_ai=on_meta_ai(cmd.stats), tool_kwargs=Dict(:ctx => ctx))
    cmd.result = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    cmd
end

ToolCallFormat.result2string(cmd::ExploreToolCall) = something(cmd.result, "(no result)")

# --- The generator (holds config, handed to agent at setup) ---
@kwdef struct ExploreTool <: AbstractToolGenerator
    tools::Vector
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::ExploreTool) = EXPLORE_TAG

const EXPLORE_SCHEMA = (
    name = EXPLORE_TAG,
    description = "Launch a read-only sub-agent to explore the codebase. Returns the agent's final summary. Use for searching files, understanding code structure, reading implementations.",
    params = [
        (name = "query", type = "string", description = "The exploration task or question for the sub-agent", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::ExploreTool) = EXPLORE_SCHEMA
ToolCallFormat.get_description(::ExploreTool) = description_from_schema(EXPLORE_SCHEMA)

function ToolCallFormat.create_tool(et::ExploreTool, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    ExploreToolCall(; query, tools=et.tools, model=et.model)
end
