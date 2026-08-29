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

review_sys_prompt(tools) = """You are a review and advisory agent. Your job is to evaluate whether the original goal was accomplished optimally.

Use git diff, git status, read files, and search to understand what was done. Then:
- Assess whether the goal was fully and correctly achieved
- Identify issues, bugs, or missing pieces
- Suggest simpler or cleaner approaches that could achieve the same goal
- Propose alternative solutions or architectural improvements
- Question whether the approach taken was the best path

$(opencode_gemini_understand_prompt)
$(machine_routing_block(tools; stale_tail="Cloud repos can be stale: never modify without `git fetch && git status` first."))
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
        sys_msg = review_sys_prompt(cmd.tools),
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
    description = "Launch a read-only review sub-agent: it inspects the change (git diff/status, files) in its own context and returns only a findings report — issues, missing pieces, simpler alternatives. Run it on non-trivial changes before calling them done.",
    params = [
        (name = "prompt", type = "string", description = "The review task: include the original goal, context, and what to review", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::ReviewTool) = REVIEW_SCHEMA
ToolCallFormat.get_tool_schema(::Type{ReviewToolCall}) = REVIEW_SCHEMA
ToolCallFormat.get_description(::ReviewTool) = description_from_schema(REVIEW_SCHEMA)

function ToolCallFormat.create_tool(rt::ReviewTool, call::ParsedCall)
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    ReviewToolCall(; prompt, tools=rt.tools, model=rt.model, extractor_type=rt.extractor_type)
end
