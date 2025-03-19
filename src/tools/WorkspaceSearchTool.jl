
@kwdef mutable struct WorkspaceSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    workspace_ctx::Union{Nothing,WorkspaceCTX} = nothing
    result::String = ""
end

function WorkspaceSearchTool(cmd::ToolTag, workspace_ctx::WorkspaceCTX=nothing)
    # Convert the root_path to a vector of strings as expected by WorkspaceCTX constructor
    workspace_ctx = workspace_ctx
    WorkspaceSearchTool(query=cmd.args, workspace_ctx=workspace_ctx)
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
    result, _ = process_workspace_context(tool.workspace_ctx, tool.query)
    tool.result = result
    true
end

function result2string(tool::WorkspaceSearchTool)
    isempty(tool.result) && return "No relevant code found for query: $(tool.query)"
    """
    Search results for: $(tool.query)
    
    $(tool.result)"""
end
