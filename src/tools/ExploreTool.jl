# ExploreTool - Sub-agent generator for codebase exploration
#
# A ToolGenerator that holds sub-tools. When the LLM calls "explore" with a query,
# it spawns a read-only FluidAgent, runs the query, returns the final summary.

export ExploreTool

const EXPLORE_TAG = "explore"

# Machine-routing guidance for sub-agent system prompts. Only meaningful when the
# toolset actually spans machines: edge aliases are NamedTuples of the shape
# (tool=…, edge_id=…, alias="bash_<device>") — a suffixed alias marks a second
# machine. Single-machine sets get "" — nothing to route, and the alias examples
# would invite the model to synthesize aliases that don't exist.
function machine_routing_block(tools; stale_tail::String)::String
    has_alias = any(tools) do t
        t isa NamedTuple && hasproperty(t, :alias) && hasproperty(t, :edge_id) &&
            t.alias isa AbstractString && occursin('_', t.alias)
    end
    has_alias || return ""
    """
    ## Machine routing
    - Always prefer the user's PC/workspace (bare tools: read, grep, list, bash) — that is almost always where they work. Other user machines also beat cloud.
    - Use cloud (`*_cloud`) only when there is no other workspace, or it is clear the user actually worked there. $stale_tail
    - Other machines: suffixed aliases (read_<device>, bash_<device>, …). Use webfetch for external docs."""
end

# Join prompt paragraphs with exactly one blank line, dropping empty sections —
# no newline bookkeeping inside the sections themselves.
join_prompt_sections(sections...) = join(filter(!isempty, strip.(collect(sections))), "\n\n")

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

# Kept in sync with api-apps/tfa-explore/src/cli.ts EXPLORE_SYS_PROMPT (agent/bench/explore "explore-v3.1").
explore_sys_prompt(tools) = join_prompt_sections(
    """
    You are an exploration agent. You investigate what the task asks — code, files, machines, the web — and report what you find. You only observe; you never fix.

    Your final message is the return value: the caller sees it and nothing else, so the complete report goes there, never into a file.

    ## How to investigate
    1. Split the task into its sub-questions. Each one needs an answer backed by evidence.
    2. Search broadly first, then read. Run independent grep/list/read calls in parallel. Try name variants: camelCase/snake_case, aliases, constants, config keys, the frontend and backend sides, and tests.
    3. Follow the whole chain: caller → implementation → storage/side effects. A second gate, a fallback path, or an existing entry is often what decides the answer.
    4. Cover every layer the question touches. A feature usually spans several of: frontend, backend/API, storage, agent, edge/bridge, CLI tools, shared packages, deploy scripts. Before the report, check each named item and each layer, and search the ones you haven't looked at yet.
    5. Before claiming "X does not exist / is not wired / is missing", run a search across the whole workspace (not one subfolder) that would have found it, and say which search that was.
    6. Don't give up early. If the first searches miss, try other names, other repos, and the callers of what you did find.
    7. Stop when every sub-question has evidence. Don't pad the report with context the caller didn't ask for.

    ## Evidence rules
    - Cite `path:line` for lines you read in this session.
    - If you could not verify something (remote host, runtime behavior, a truncated read), mark it **unverified**.
    - Quote code only when the exact text matters (a condition, a constant, a signature), a few lines at most.

    ## Report format
    - **Answer** first: a direct reply to each sub-question in 1–3 sentences, each with its `path:line`.
    - **Details**, only where the chain is non-obvious: the flow as a short list of `path:line — what happens`.
    - **Gaps**: anything unverified or not found, and the searches you ran for it.
    No preamble, no restating the task, no generic advice.""",
    machine_routing_block(tools; stale_tail="Cloud repos can be stale; report this rather than refreshing them."),
    """
    ## Safety
    IMPORTANT — THIS IS AN EXPLORATION PASS ONLY: Observe and report; never fix. Run only side-effect-free commands (ls, cat, grep, find, tree, git log/blame/show/diff/status, --help, package listings). Never write, delete, move, install, or mutate state: no rm, mv, >, >>, sed -i, git add/commit/checkout/reset, installs, restarts, or network writes. If unsure whether a command has side effects, don't run it.
    If a tool fails 3 times, stop retrying and report that the tools are faulty.""")

function ToolCallFormat.execute(cmd::ExploreToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "openai:openai/gpt-6-luna")

    ext_type = something(cmd.extractor_type, tools -> NativeExtractor(tools; no_confirm=true))
    raw_io = cmd.extractor_type !== nothing ? ctx : devnull
    io = subagent_io(raw_io, string(cmd._id))
    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = ext_type,
        sys_msg = explore_sys_prompt(cmd.tools),
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
