using ToolCallFormat: ParsedCall

@kwdef mutable struct WorkspaceSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    workspace_ctx::Union{Nothing,WorkspaceCTX} = nothing
    result::String = ""
    workspace_ctx_result::Union{Nothing,WorkspaceCTXResult} = nothing
end

function create_tool(::Type{WorkspaceSearchTool}, call::ParsedCall, workspace_ctx::WorkspaceCTX=nothing)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    WorkspaceSearchTool(query=query, workspace_ctx=workspace_ctx)
end


toolname(::Type{WorkspaceSearchTool}) = "workspace_search"
tool_format(::Type{WorkspaceSearchTool}) = :single_line

const WORKSPACESEARCH_SCHEMA = (
    name = "workspace_search",
    description = "Semantic search in workspace for code and files",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
get_tool_schema(::Type{WorkspaceSearchTool}) = WORKSPACESEARCH_SCHEMA
get_description(::Type{WorkspaceSearchTool}) = description_from_schema(WORKSPACESEARCH_SCHEMA)

function execute(tool::WorkspaceSearchTool; no_confirm=false)
    if isnothing(tool.workspace_ctx)
        @warn "workspace_ctx is nothing, this should never happen!" 
        return false
    end
    
    result, _, _, full_result = process_workspace_context(tool.workspace_ctx, tool.query)
    
    tool.result = result
    tool.workspace_ctx_result = full_result
    
    true
end

function result2string(tool::WorkspaceSearchTool)
    isempty(tool.result) && return "No relevant code found for query: $(tool.query)"
    """
    Search results for: $(tool.query)
    
    $(tool.result)"""
end

function get_cost(tool::WorkspaceSearchTool)
    return tool.cost
end


EasyContext.execute_required_tools(::WorkspaceSearchTool) = true