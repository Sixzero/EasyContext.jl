import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractTool, description_from_schema

@kwdef mutable struct CreateFileTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "txt"
    file_path::String
    root_path::Union{String, AbstractPath, Nothing} = nothing
    content::String
end

function ToolCallFormat.create_tool(::Type{CreateFileTool}, call::ParsedCall, root_path=nothing)
    file_path_pv = get(call.kwargs, "file_path", nothing)
    file_path = file_path_pv !== nothing ? file_path_pv.value : ""
    file_path = endswith(file_path, ">") ? chop(file_path) : file_path

    content_pv = get(call.kwargs, "content", nothing)
    raw_content = content_pv !== nothing ? content_pv.value : call.content
    language, content = parse_code_block(raw_content)

    root_path_pv = get(call.kwargs, "root_path", nothing)
    root_path = root_path === nothing ? (root_path_pv !== nothing ? root_path_pv.value : nothing) : root_path
    CreateFileTool(; language, file_path, root_path, content)
end

ToolCallFormat.tool_format(::Type{CreateFileTool}) = :multi_line
ToolCallFormat.execute_required_tools(::CreateFileTool) = false
ToolCallFormat.toolname(::Type{CreateFileTool}) = "create_file"

const CREATEFILE_SCHEMA = (
    name = "create_file",
    description = "Create a new file with content",
    params = [
        (name = "file_path", type = "string", description = "Path for the new file", required = true),
        (name = "content", type = "codeblock", description = "File content", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::Type{CreateFileTool}) = CREATEFILE_SCHEMA
ToolCallFormat.get_description(::Type{CreateFileTool}) = description_from_schema(CREATEFILE_SCHEMA)

function ToolCallFormat.execute(tool::CreateFileTool; no_confirm=false, kwargs...)
    path = expand_path(tool.file_path, tool.root_path)

    shell_cmd = process_create_command(path, tool.content)
    shortened_code = get_shortened_code(shell_cmd, 4, 2)
    print_code(shortened_code)

    dir = dirname(path)
    !isdir(dir) && mkpath(dir)

    if no_confirm || get_user_confirmation()
        print_output_header()
        execute_with_output(`zsh -c $shell_cmd`)
    else
        "\nOperation cancelled by user."
    end
end

function process_create_command(file_path::String, content::String)
    delimiter = get_unique_eof(content)
    escaped_path = replace(file_path, r"[\[\]()]" => s"\\\0")
    "cat > $(escaped_path) <<'$delimiter'\n$(content)\n$delimiter"
end
