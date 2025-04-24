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
instantiate(::Val{Symbol(JULIA_SEARCH_TAG)}, cmd::ToolTag) = JuliaSearchTool(cmd)

stop_sequence(cmd::Type{JuliaSearchTool}) = STOP_SEQUENCE
toolname(::Type{JuliaSearchTool}) = JULIA_SEARCH_TAG
tool_format(::Type{JuliaSearchTool}) = :single_line

function get_description(::Type{JuliaSearchTool})
    """
    Search through Julia packages using semantic search:
    $JULIA_SEARCH_TAG your search query [$STOP_SEQUENCE]
    
    $STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
    """
end

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
