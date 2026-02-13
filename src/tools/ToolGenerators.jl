export AbstractToolGenerator, ToolGenerator, WorkspaceToolGenerator

# Types imported via ToolInterface.jl

abstract type AbstractToolGenerator end

ToolCallFormat.get_extra_description(::AbstractToolGenerator) = nothing
ToolCallFormat.get_description(tool::AbstractToolGenerator) = get_description(typeof(tool))
ToolCallFormat.get_cost(::AbstractToolGenerator) = nothing

struct ToolGenerator <: AbstractToolGenerator
    tool_type::DataType
    args
end

function ToolCallFormat.create_tool(tg::ToolGenerator, call::ParsedCall)
    create_tool(tg.tool_type, call; tg.args...)
end

ToolCallFormat.toolname(tg::ToolGenerator) = toolname(tg.tool_type)
ToolCallFormat.get_description(tg::ToolGenerator) = get_description(tg.tool_type)
ToolCallFormat.get_tool_schema(tg::ToolGenerator) = get_tool_schema(tg.tool_type)

@kwdef mutable struct WorkspaceToolGenerator <: AbstractToolGenerator
    edge_id::String
    workspace_context::WorkspaceCTX
end

function ToolCallFormat.create_tool(wtg::WorkspaceToolGenerator, call::ParsedCall)
    create_tool(WorkspaceSearchTool, call, wtg.workspace_context)
end

ToolCallFormat.toolname(::WorkspaceToolGenerator) = toolname(WorkspaceSearchTool)
ToolCallFormat.get_description(::WorkspaceToolGenerator) = get_description(WorkspaceSearchTool)
ToolCallFormat.get_tool_schema(::WorkspaceToolGenerator) = get_tool_schema(WorkspaceSearchTool)
ToolCallFormat.get_extra_description(tg::WorkspaceToolGenerator) = workspace_format_description_raw(tg.workspace_context.workspace)

ToolCallFormat.get_id(tool::AbstractToolGenerator) = hasproperty(tool, :tool) ? tool.tool._id : nothing
ToolCallFormat.is_cancelled(::AbstractToolGenerator) = false
ToolCallFormat.resultimg2base64(::AbstractToolGenerator) = nothing
ToolCallFormat.resultaudio2base64(::AbstractToolGenerator) = nothing
