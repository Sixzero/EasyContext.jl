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
    timeout::Union{Int, Nothing} = 900
    stats::SubAgentStats = SubAgentStats()
    process_result::Union{ProcessResult, Nothing} = nothing
end

ToolCallFormat.get_id(t::ExploreToolCall) = t._id
ToolCallFormat.toolname(::Type{ExploreToolCall}) = EXPLORE_TAG
LLM_safetorun(::ExploreToolCall) = true

const EXPLORE_SYS_PROMPT = """You are a codebase exploration agent. Read files, run shell commands, fetch web pages, and report findings.

$(opencode_gemini_understand_prompt)

Default tools (read, grep, list, bash) target the primary device, where the workspace lives — usually the user's machine or a server device, rarely the cloud. Prefer them. To inspect a different machine, call its suffixed alias (read_<device>, grep_<device>, list_<device>, bash_<device>, e.g. read_pc_6). Use webfetch to pull in external docs or pages when relevant.

IMPORTANT — THIS IS AN EXPLORATION PASS ONLY: You observe and note things; you NEVER modify anything. You are not here to fix problems — you find and report them, and a later agent will make the corrections based on your findings. You have a real shell, so honoring this is on you: run ONLY non-destructive, side-effect-free commands (e.g. ls, cat, grep, find, tree, git log/blame/show/diff/status, --help, package listings). NEVER run anything that writes, deletes, moves, installs, or mutates state (no rm, mv, >, >>, sed -i, git add/commit/checkout/reset, package installs, service restarts, network writes). Before running a command, confirm it is purely observational; if unsure whether it has side effects, do not run it. Do not modify, create, or delete any files — just note what should change.
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
    description = "Launch a read-only sub-agent to explore the codebase. It works in its OWN context window (its many file reads/greps never touch yours) and returns only its final report — a distilled summary of what it found. So you get the right answer fast without spending your own context. PREFER this over manually reading/searching many files for any non-trivial \"where/how/what is\" question. Use for searching files, understanding code structure, reading implementations.",
    params = [
        (name = "prompt", type = "string", description = "The exploration task or question for the sub-agent", required = true),
        (name = "timeout", type = "integer", description = "Timeout in seconds for the sub-agent (default: 900)", required = false, default = 900),
    ]
)

ToolCallFormat.get_tool_schema(::ExploreTool) = EXPLORE_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ExploreToolCall}) = EXPLORE_SCHEMA
ToolCallFormat.get_description(::ExploreTool) = description_from_schema(EXPLORE_SCHEMA)

function ToolCallFormat.create_tool(et::ExploreTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    timeout_pv = get(call.kwargs, "timeout", nothing)
    timeout = timeout_pv !== nothing ? Int(timeout_pv.value) : 900
    ExploreToolCall(; prompt, timeout, tools=et.tools, model=et.model, extractor_type=et.extractor_type)
end
