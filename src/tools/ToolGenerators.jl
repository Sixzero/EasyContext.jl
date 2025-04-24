export AbstractToolGenerator, ToolGenerator, WorkspaceToolGenerator, toolname

abstract type AbstractToolGenerator end
get_extra_description(tg::AbstractToolGenerator) = nothing

get_description(tool::AbstractToolGenerator)::String = get_description(typeof(tool))
has_stop_sequence(tool::AbstractToolGenerator)::Bool = has_stop_sequence(typeof(tool))
has_stop_sequence(tool::Type{<:AbstractToolGenerator})::Bool = stop_sequence(tool) != "" 
get_cost(tool::AbstractToolGenerator) = nothing

struct ToolGenerator <: AbstractToolGenerator
    tool_type::DataType
    args
end
function create_tool(tg::ToolGenerator, cmd::ToolTag)
    tg.tool_type(cmd; tg.args...)
end

toolname(tg::ToolGenerator) = toolname(tg.tool_type)
get_description(tg::ToolGenerator) = get_description(tg.tool_type)
has_stop_sequence(tg::ToolGenerator) = has_stop_sequence(tg.tool_type)
stop_sequence(tg::ToolGenerator) = stop_sequence(tg.tool_type)
tool_format(tg::ToolGenerator) = tool_format(tg.tool_type)


@kwdef mutable struct WorkspaceToolGenerator <: AbstractToolGenerator
    workspace_context::WorkspaceCTX
    io::Union{IO, Nothing} = nothing
end
function create_tool(wtg::WorkspaceToolGenerator, cmd::ToolTag)
    WorkspaceSearchTool(cmd, wtg.workspace_context, wtg.io)
end

toolname(tg::WorkspaceToolGenerator) = toolname(WorkspaceSearchTool)
get_description(tg::WorkspaceToolGenerator) = get_description(WorkspaceSearchTool)
get_extra_description(tg::WorkspaceToolGenerator) = workspace_format_description_raw(tg.workspace_context.workspace)
has_stop_sequence(tg::WorkspaceToolGenerator) = has_stop_sequence(WorkspaceSearchTool)
stop_sequence(tg::WorkspaceToolGenerator) = stop_sequence(WorkspaceSearchTool)
tool_format(tg::WorkspaceToolGenerator) = tool_format(WorkspaceSearchTool)

EasyContext.preprocess(tool::AbstractToolGenerator) = tool
EasyContext.get_id(tool::AbstractToolGenerator) = tool.tool.id
EasyContext.is_cancelled(tool::AbstractToolGenerator) = false