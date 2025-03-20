export AbstractToolGenerator, ToolGenerator, WorkspaceToolGenerator, toolname

abstract type AbstractToolGenerator end

struct ToolGenerator <: AbstractToolGenerator
    tool_type::DataType
    args
end
function (tg::ToolGenerator)(cmd::ToolTag)
    tg.tool_type(cmd; tg.args...)
end

toolname(tg::ToolGenerator) = toolname(tg.tool_type)
get_description(tg::ToolGenerator) = get_description(tg.tool_type)
has_stop_sequence(tg::ToolGenerator) = has_stop_sequence(tg.tool_type)
stop_sequence(tg::ToolGenerator) = stop_sequence(tg.tool_type)
tool_format(tg::ToolGenerator) = tool_format(tg.tool_type)


@kwdef struct WorkspaceToolGenerator <: AbstractToolGenerator
    workspace_context::WorkspaceCTX
end
function (wtg::WorkspaceToolGenerator)(cmd::ToolTag)
    WorkspaceSearchTool(cmd, wtg.workspace_context)
end

toolname(tg::WorkspaceToolGenerator) = toolname(WorkspaceSearchTool)
get_description(tg::WorkspaceToolGenerator) = get_description(WorkspaceSearchTool)
has_stop_sequence(tg::WorkspaceToolGenerator) = has_stop_sequence(WorkspaceSearchTool)
stop_sequence(tg::WorkspaceToolGenerator) = stop_sequence(WorkspaceSearchTool)
tool_format(tg::WorkspaceToolGenerator) = tool_format(WorkspaceSearchTool)
