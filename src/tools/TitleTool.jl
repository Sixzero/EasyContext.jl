# TitleTool - Sub-agent generator for conversation title generation
#
# No sub-tools needed. Spawns a minimal FluidAgent that generates a ≤50 char title.

export TitleTool

const TITLE_TAG = "title"

# --- The actual tool instance created per LLM call ---
@kwdef mutable struct TitleToolCall <: ToolCallFormat.AbstractTool
    _id::UUID = uuid4()
    query::String
    model::Union{String, Nothing}
    result::Union{String, Nothing} = nothing
end

ToolCallFormat.get_id(t::TitleToolCall) = t._id
LLM_safetorun(::TitleToolCall) = true

function ToolCallFormat.execute(cmd::TitleToolCall, ctx::ToolCallFormat.AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    agent = create_FluidAgent(model;
        tools = [],
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = opencode_title_prompt,
    )
    response = work(agent, cmd.query; io=devnull, quiet=true)
    content = response !== nothing ? strip(something(response.content, "Untitled")) : "Untitled"
    cmd.result = content
    cmd
end

ToolCallFormat.result2string(cmd::TitleToolCall) = something(cmd.result, "Untitled")

# --- The generator ---
@kwdef struct TitleTool <: AbstractToolGenerator
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::TitleTool) = TITLE_TAG

const TITLE_SCHEMA = (
    name = TITLE_TAG,
    description = "Generate a short (≤50 char) conversation title from the user's message.",
    params = [
        (name = "query", type = "string", description = "The user message to generate a title for", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::TitleTool) = TITLE_SCHEMA
ToolCallFormat.get_description(::TitleTool) = description_from_schema(TITLE_SCHEMA)

function ToolCallFormat.create_tool(tt::TitleTool, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    TitleToolCall(; query, model=tt.model)
end
