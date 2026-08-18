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

const EXPLORE_SYS_PROMPT = """You are an exploration agent: you own the investigation the task asks for — code, files, machines, the web — and you report what you find.

Read files, run side-effect-free shell commands, fetch web pages. Your final message is the return value: the caller sees that message and nothing else, so the complete report goes there, never into a file.

$(opencode_gemini_understand_prompt)

MACHINE ROUTING:
- Always prefer the user's PC/workspace (bare tools: read, grep, list, bash) — that is almost always where they work. Other user machines also beat cloud.
- Use cloud (`*_cloud`) only when there is no other workspace, or it is clear the user actually worked there. Cloud repos can be stale; report this rather than refreshing them.
- Other machines: suffixed aliases (read_<device>, bash_<device>, …). Use webfetch for external docs.

IMPORTANT — THIS IS AN EXPLORATION PASS ONLY: Observe and report; never fix. Run only non-destructive, side-effect-free commands (e.g. ls, cat, grep, find, tree, git log/blame/show/diff/status, --help, package listings). NEVER run anything that writes, deletes, moves, installs, or mutates state (no rm, mv, >, >>, sed -i, git add/commit/checkout/reset, package installs, service restarts, network writes). Before running a command, confirm it is purely observational; if unsure whether it has side effects, do not run it.
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
    description = "Launch a read-only sub-agent to explore. It works in its OWN context window (its many reads/greps never touch yours) and returns its findings as a single distilled report. PREFER it over manual searching for non-trivial questions about where code lives, how it works, or what it does. Use it for searching files, understanding code structure, and reading implementations.",
    params = [
        (name = "prompt", type = "string", description = "The exploration task or question for the sub-agent", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::ExploreTool) = EXPLORE_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ExploreToolCall}) = EXPLORE_SCHEMA
ToolCallFormat.get_description(::ExploreTool) = description_from_schema(EXPLORE_SCHEMA)

function ToolCallFormat.create_tool(et::ExploreTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    ExploreToolCall(; prompt, tools=et.tools, model=et.model, extractor_type=et.extractor_type)
end
