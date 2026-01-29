import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractTool, description_from_schema

@kwdef mutable struct CatFileTool <: AbstractTool
    id::UUID = uuid4()
    file_path::Union{String, AbstractPath}
    root_path::Union{String, AbstractPath, Nothing} = nothing
    line_start::Union{Int, Nothing} = nothing
    line_end::Union{Int, Nothing} = nothing
    result::String = ""
end

"""
Parse file path with optional line range: `file:start-end`, `file:start-`, `file:-N` (tail)
Returns (file_path, line_start, line_end) - negative line_start means tail N lines
"""
function parse_file_range(args::String)
    m = match(r"^(.+?):(-\d+)$", args)
    m !== nothing && return (m[1], parse(Int, m[2]), nothing)

    m = match(r"^(.+?):(\d+)-(\d*)$", args)
    m !== nothing && return (m[1], parse(Int, m[2]), m[3] != "" ? parse(Int, m[3]) : nothing)

    m = match(r"^(.+?):(\d+)$", args)
    if m !== nothing
        line = parse(Int, m[2])
        return (m[1], line, line)
    end
    (args, nothing, nothing)
end

function ToolCallFormat.create_tool(::Type{CatFileTool}, call::ParsedCall, root_path=nothing)
    file_path_pv = get(call.kwargs, "file_path", nothing)
    file_path_str = file_path_pv !== nothing ? file_path_pv.value : ""
    file_path, line_start, line_end = parse_file_range(file_path_str)
    root_path_pv = get(call.kwargs, "root_path", nothing)
    root_path = root_path === nothing ? (root_path_pv !== nothing ? root_path_pv.value : nothing) : root_path
    CatFileTool(; id=uuid4(), file_path, root_path, line_start, line_end)
end

ToolCallFormat.toolname(::Type{CatFileTool}) = "cat_file"

const CATFILE_SCHEMA = (
    name = "cat_file",
    description = "Read file content. Supports line ranges: file:10-20, file:10-, file:-20 (tail)",
    params = [(name = "file_path", type = "string", description = "Path to file, optionally with line range", required = true)]
)

ToolCallFormat.get_tool_schema(::Type{CatFileTool}) = CATFILE_SCHEMA
ToolCallFormat.get_description(::Type{CatFileTool}) = description_from_schema(CATFILE_SCHEMA)
ToolCallFormat.tool_format(::Type{CatFileTool}) = :single_line

function ToolCallFormat.execute(cmd::CatFileTool; no_confirm::Bool=false, kwargs...)
    path = expand_path(cmd.file_path, cmd.root_path)
    cmd.result = isfile(path) ? file_format(format_path(cmd), extract_lines(read(path, String), cmd.line_start, cmd.line_end)) : "cat: $(path): No such file or directory"
end

format_path(cmd::CatFileTool) = cmd.line_start === nothing ? cmd.file_path :
    cmd.line_start < 0 ? "$(cmd.file_path):$(cmd.line_start)" :
    cmd.line_end === nothing ? "$(cmd.file_path):$(cmd.line_start)-" : "$(cmd.file_path):$(cmd.line_start)-$(cmd.line_end)"

extract_lines(content::String, ::Nothing, _) = content
function extract_lines(content::String, line_start::Int, line_end)
    lines = split(content, '\n')
    n = length(lines)
    if line_start < 0
        start_idx = max(1, n + line_start + 1)
        return join(lines[start_idx:n], '\n')
    end
    join(lines[clamp(line_start, 1, n):clamp(something(line_end, n), line_start, n)], '\n')
end

LLM_safetorun(::CatFileTool) = true
ToolCallFormat.result2string(tool::CatFileTool)::String = tool.result
ToolCallFormat.execute_required_tools(::CatFileTool) = true
