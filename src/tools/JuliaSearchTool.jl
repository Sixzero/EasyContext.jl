import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractTool, description_from_schema

@kwdef mutable struct JuliaSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    julia_ctx::Union{Nothing,JuliaCTX} = nothing
    result::String = ""
end

function ToolCallFormat.create_tool(::Type{JuliaSearchTool}, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    model_pv = get(call.kwargs, "model", nothing)
    model = model_pv !== nothing ? model_pv.value : ["gem20f", "gem15f", "gpt4om"]
    julia_ctx = init_julia_context(; model)
    JuliaSearchTool(query=query, julia_ctx=julia_ctx)
end

ToolCallFormat.toolname(::Type{JuliaSearchTool}) = "julia_search"
ToolCallFormat.tool_format(::Type{JuliaSearchTool}) = :single_line

const JULIASEARCH_SCHEMA = (
    name = "julia_search",
    description = "Search Julia packages and documentation",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)

ToolCallFormat.get_tool_schema(::Type{JuliaSearchTool}) = JULIASEARCH_SCHEMA
ToolCallFormat.get_description(::Type{JuliaSearchTool}) = description_from_schema(JULIASEARCH_SCHEMA)

function ToolCallFormat.execute(tool::JuliaSearchTool; no_confirm=false, kwargs...)
    if isnothing(tool.julia_ctx)
        @warn "julia_ctx is nothing"
        return false
    end
    result, _ = process_julia_context(tool.julia_ctx, tool.query)
    tool.result = result
    true
end

function ToolCallFormat.result2string(tool::JuliaSearchTool)
    isempty(tool.result) && return "No relevant Julia code found for query: $(tool.query)"
    """
Julia search results for: $(tool.query)

$(tool.result)"""
end
