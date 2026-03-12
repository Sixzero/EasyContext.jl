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
    prompt::String
    tools::Vector
    model::Union{String, Nothing}
    extractor_type::Union{Function, Nothing} = nothing
    timeout::Union{Int, Nothing} = 300
    stats::SubAgentStats = SubAgentStats()
    process_result::Union{ProcessResult, Nothing} = nothing
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

    ext_type = something(cmd.extractor_type, tools -> NativeExtractor(tools; no_confirm=true))
    raw_io = cmd.extractor_type !== nothing ? ctx : devnull
    io = subagent_io(raw_io, string(cmd._id))
    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = ext_type,
        sys_msg = EXPLORE_SYS_PROMPT,
    )
    response = work(agent, cmd.prompt; io=io, quiet=true, on_meta_ai=on_meta_ai(cmd.stats),
        tool_kwargs=Dict(:ctx => ctx))
    cmd.process_result = ProcessResult(response !== nothing ? something(response.content, "(no response)") : "(no response)")
    cmd
end


# --- The generator (holds config, handed to agent at setup) ---
@kwdef struct ExploreTool <: AbstractToolGenerator
    tools::Vector
    model::Union{String, Nothing} = nothing
    extractor_type::Union{Function, Nothing} = nothing
end

ToolCallFormat.toolname(::ExploreTool) = EXPLORE_TAG

const EXPLORE_SCHEMA = (
    name = EXPLORE_TAG,
    description = "Launch a read-only sub-agent to explore the codebase. Returns the agent's final summary. Use for searching files, understanding code structure, reading implementations.",
    params = [
        (name = "prompt", type = "string", description = "The exploration task or question for the sub-agent", required = true),
        (name = "timeout", type = "integer", description = "Timeout in seconds for the sub-agent (default: 300)", required = false, default = 300),
    ]
)

ToolCallFormat.get_tool_schema(::ExploreTool) = EXPLORE_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ExploreToolCall}) = EXPLORE_SCHEMA
ToolCallFormat.get_description(::ExploreTool) = description_from_schema(EXPLORE_SCHEMA)

function ToolCallFormat.create_tool(et::ExploreTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    timeout_pv = get(call.kwargs, "timeout", nothing)
    timeout = timeout_pv !== nothing ? Int(timeout_pv.value) : 300
    ExploreToolCall(; prompt, timeout, tools=et.tools, model=et.model, extractor_type=et.extractor_type)
end
