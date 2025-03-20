export AbstractToolGenerator, ToolGenerator, WorkspaceToolGenerator, toolname

abstract type AbstractToolGenerator end
struct ToolGenerator <: AbstractToolGenerator
    tool_type::DataType
    args
end
function (tg::ToolGenerator)(cmd::ToolTag)
    tg.tool_type(cmd; tg.args...)
end
@kwdef struct WorkspaceToolGenerator <: AbstractToolGenerator
    workspace_context::WorkspaceCTX
end
function (wtg::WorkspaceToolGenerator)(cmd::ToolTag)
    WorkspaceSearchTool(cmd, wtg.workspace_context)
end

toolname(tg::ToolGenerator) = toolname(tg.tool_type)
toolname(tg::WorkspaceToolGenerator) = toolname(WorkspaceSearchTool)

get_description(tg::ToolGenerator) = get_description(tg.tool_type)
get_description(tg::WorkspaceToolGenerator) = get_description(WorkspaceSearchTool)

has_stop_sequence(tg::ToolGenerator) = has_stop_sequence(tg.tool_type)
has_stop_sequence(tg::WorkspaceToolGenerator) = has_stop_sequence(WorkspaceSearchTool)

stop_sequence(tg::ToolGenerator) = stop_sequence(tg.tool_type)
stop_sequence(tg::WorkspaceToolGenerator) = stop_sequence(WorkspaceSearchTool)

tool_format(tg::ToolGenerator) = tool_format(tg.tool_type)
tool_format(tg::WorkspaceToolGenerator) = tool_format(WorkspaceSearchTool)


function assign_client!(tool::WorkspaceToolGenerator, client::APIClient, edge_id::String, agent_id::String)
    tool.workspace_context.workspace.client = client
    edge_id != nothing && edge_id != tool.workspace_context.workspace.edge_id && @warn "Edge id changed."
    tool.workspace_context.workspace.edge_id = edge_id
    agent_id != nothing && agent_id != tool.workspace_context.workspace.agent_id && @warn "Agent id changed."
    tool.workspace_context.workspace.agent_id = agent_id
end

function reset_client!(tool::WorkspaceToolGenerator)
    tool.workspace_context.workspace.client = nothing # we are not resetting edge_id and agent_id, because it might be worth to check later if it is changing between runs
end