# SummarizeTool - Sub-agent generator for file summarization
#
# No sub-tools. Reads the file, sends content + prompt to a single LLM call.

export SummarizeTool

const SUMMARIZE_TAG = "summarize"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct SummarizeToolCall <: ToolCallFormat.AbstractTool
    _id::UUID = uuid4()
    path::String
    prompt::String
    root_path::Union{Nothing, String}
    model::Union{String, Nothing}
end

ToolCallFormat.get_id(t::SummarizeToolCall) = t._id
LLM_safetorun(::SummarizeToolCall) = true

const _summarize_results = Dict{UUID, String}()

const SUMMARIZE_SYS_PROMPT = "You summarize file contents. Be concise, accurate, and focus on what the user asks. Output only the summary."

function ToolCallFormat.execute(cmd::SummarizeToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")
    path = expand_path(cmd.path, cmd.root_path)

    if !isfile(path)
        _summarize_results[cmd._id] = "Error: file not found: $path"
        return cmd
    end

    content = read(path, String)
    user_msg = """$(cmd.prompt)

File: $(cmd.path)
```
$content
```"""

    agent = create_FluidAgent(model;
        tools = [],
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = SUMMARIZE_SYS_PROMPT,
    )
    agent.tool_mode = :native

    response = work(agent, user_msg; io=devnull, quiet=true)
    result = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    _summarize_results[cmd._id] = result
    cmd
end

ToolCallFormat.result2string(cmd::SummarizeToolCall) = pop!(_summarize_results, cmd._id, "(no result)")

# --- The generator ---
@kwdef struct SummarizeTool <: AbstractToolGenerator
    root_path::Union{Nothing, String} = nothing
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::SummarizeTool) = SUMMARIZE_TAG

const SUMMARIZE_SCHEMA = (
    name = SUMMARIZE_TAG,
    description = "Summarize a file's contents based on a prompt. Reads the file and returns a focused summary.",
    params = [
        (name = "path", type = "string", description = "Path to the file to summarize", required = true),
        (name = "prompt",     type = "string", description = "What to focus on in the summary", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::SummarizeTool) = SUMMARIZE_SCHEMA
ToolCallFormat.get_description(::SummarizeTool) = description_from_schema(SUMMARIZE_SCHEMA)

function ToolCallFormat.create_tool(st::SummarizeTool, call::ParsedCall)
    path_pv = get(call.kwargs, "path", nothing)
    path = path_pv !== nothing ? path_pv.value : ""
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : "Summarize this file."
    SummarizeToolCall(; path, prompt, root_path=st.root_path, model=st.model)
end
