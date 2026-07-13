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
    timeout::Union{Int, Nothing} = 900
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

Default tools (read, grep, list, bash) target the primary device, where the workspace lives — usually the user's machine or a server device, rarely the cloud. Prefer them. To inspect a different machine, call its suffixed alias (read_<device>, grep_<device>, list_<device>, bash_<device>, e.g. read_pc_6). Use webfetch to pull in external docs or pages when relevant.

IMPORTANT — THIS IS A REVIEW PASS ONLY: You observe and note things; you NEVER modify anything. You are not here to apply fixes — you find issues and report them, and a later agent will make the corrections based on your findings. You have a real shell, so honoring this is on you: run ONLY non-destructive, side-effect-free commands (e.g. ls, cat, grep, find, tree, git log/blame/show/diff/status, --help, package listings). NEVER run anything that writes, deletes, moves, installs, or mutates state (no rm, mv, >, >>, sed -i, git add/commit/checkout/reset, package installs, service restarts, network writes). Before running a command, confirm it is purely observational; if unsure whether it has side effects, do not run it. Do not modify, create, or delete any files — just note what should change.
If a tool fails 3 times, stop retrying and report that the tools are faulty."""

function ToolCallFormat.execute(cmd::ReviewToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "openai:openai/gpt-5.6-sol")

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
    description = "Launch a read-only sub-agent to evaluate whether a goal was accomplished optimally. It works in its OWN context window (inspects git diff/status, reads files — none of which touch yours) and returns only its final report: its findings on the change. So the check costs little of your own context. When a change is non-trivial enough to be worth a second look, run it before calling the work done. Reviews changes, suggests simplifications, proposes alternative approaches, and identifies issues.",
    params = [
        (name = "prompt", type = "string", description = "The review task: include the original goal, context, and what to review", required = true),
        (name = "timeout", type = "integer", description = "Timeout in seconds for the sub-agent (default: 900)", required = false, default = 900),
    ]
)

ToolCallFormat.get_tool_schema(::ReviewTool) = REVIEW_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ReviewToolCall}) = REVIEW_SCHEMA
ToolCallFormat.get_description(::ReviewTool) = description_from_schema(REVIEW_SCHEMA)

function ToolCallFormat.create_tool(rt::ReviewTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    timeout_pv = get(call.kwargs, "timeout", nothing)
    timeout = timeout_pv !== nothing ? Int(timeout_pv.value) : 900
    ReviewToolCall(; prompt, timeout, tools=rt.tools, model=rt.model, extractor_type=rt.extractor_type)
end
