
@kwdef mutable struct WorkspaceSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    workspace_ctx::Union{Nothing,WorkspaceCTX} = nothing
    result::String = ""
    workspace_ctx_result::Union{Nothing,WorkspaceCTXResult} = nothing
end

function create_tool(::Type{WorkspaceSearchTool}, cmd::ToolTag, workspace_ctx::WorkspaceCTX=nothing)
    # Convert the root_path to a vector of strings as expected by WorkspaceCTX constructor
    WorkspaceSearchTool(query=cmd.args, workspace_ctx=workspace_ctx)
end


const WORKSPACE_SEARCH_TAG = "WORKSPACE_SEARCH"

toolname(::Type{WorkspaceSearchTool}) = WORKSPACE_SEARCH_TAG
tool_format(::Type{WorkspaceSearchTool}) = :single_line
stop_sequence(::Type{WorkspaceSearchTool}) = STOP_SEQUENCE

function get_description(::Type{WorkspaceSearchTool})
    """
    Options:
    - high_accuracy=true: Use a more accurate but slower search pipeline
    """
    # later on add it in? ^^
    """
    Search smart semantic search:
    WORKSPACE_SEARCH your search query [$STOP_SEQUENCE]
    
    If you don't have a specific function or functionality in the context, then just search for what you're looking for, stating either function names or functionality in the query. 
    
    $STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
    """
end

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