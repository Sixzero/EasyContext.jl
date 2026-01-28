@kwdef mutable struct JuliaSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    julia_ctx::Union{Nothing,JuliaCTX} = nothing
    result::String = ""
end

const JULIA_SEARCH_TAG = "JULIA_SEARCH"
function create_tool(::Type{JuliaSearchTool}, cmd::ToolTag)
    model = get(cmd.kwargs, "model", ["gem20f", "gem15f", "gpt4om"])
    julia_ctx = init_julia_context(; model)
    JuliaSearchTool(query=cmd.args, julia_ctx=julia_ctx)
end

stop_sequence(cmd::Type{JuliaSearchTool}) = STOP_SEQUENCE
toolname(::Type{JuliaSearchTool}) = "julia_search"
tool_format(::Type{JuliaSearchTool}) = :single_line
const JULIASEARCH_SCHEMA = (
    name = "julia_search",
    description = "Search Julia packages and documentation",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
get_tool_schema(::Type{JuliaSearchTool}) = JULIASEARCH_SCHEMA
get_description(::Type{JuliaSearchTool}) = description_from_schema(JULIASEARCH_SCHEMA)

function execute(tool::JuliaSearchTool; no_confirm=false)
    if isnothing(tool.julia_ctx)
        @warn "julia_ctx is nothing, this should never happen!"
        return false
    end
    result, _ = process_julia_context(tool.julia_ctx, tool.query)
    tool.result = result
    true
end

function result2string(tool::JuliaSearchTool)
    isempty(tool.result) && return "No relevant Julia code found for query: $(tool.query)"
    """
    Julia search results for: $(tool.query)
    
    $(tool.result)"""
end
