
@kwdef mutable struct WorkspaceSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    workspace_ctx::Union{Nothing,WorkspaceCTX} = nothing
    result_str::String = ""
    result::Union{Nothing,WorkspaceCTXResult} = nothing
    io::Union{IO, Nothing} = nothing
end

function WorkspaceSearchTool(cmd::ToolTag, workspace_ctx::WorkspaceCTX=nothing, io=nothing)
    # Convert the root_path to a vector of strings as expected by WorkspaceCTX constructor
    WorkspaceSearchTool(query=cmd.args, workspace_ctx=workspace_ctx, io=io)
end

const WORKSPACE_SEARCH_TAG = "WORKSPACE_SEARCH"

instantiate(::Val{Symbol(WORKSPACE_SEARCH_TAG)}, cmd::ToolTag) = WorkspaceSearchTool(cmd)

toolname(::Type{WorkspaceSearchTool}) = "WORKSPACE_SEARCH"
tool_format(::Type{WorkspaceSearchTool}) = :single_line
stop_sequence(::Type{WorkspaceSearchTool}) = STOP_SEQUENCE

function get_description(::Type{WorkspaceSearchTool})
    # TODO later on add it in?
    """
    Options:
    - high_accuracy=true: Use a more accurate but slower search pipeline
    """
    """
    Search through the codebase using semantic search:
    WORKSPACE_SEARCH your search query [$STOP_SEQUENCE]
    
    If you don't find a specific function or functionality in the context, then you can use this tool to search through the codebase for the functionality. 
    
    $STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
    """
end

function execute(tool::WorkspaceSearchTool; no_confirm=false)
    if isnothing(tool.workspace_ctx)
        @warn "workspace_ctx is nothing, this should never happen!" 
        return false
    end
    
    result_str, _, _, result::WorkspaceCTXResult = process_workspace_context(tool.workspace_ctx, tool.query; io=tool.io)
    
    tool.result_str = result_str
    tool.result = result
    
    true
end

function result2string(tool::WorkspaceSearchTool)
    isempty(tool.result_str) && return "No relevant code found for query: $(tool.query)"
    """
    Search results for: $(tool.query)
    
    $(tool.result_str)"""
end

function get_cost(tool::WorkspaceSearchTool)
    return tool.cost
end
