
@kwdef mutable struct CreateFileTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "txt"
    file_path::String
    content::String
end

function CreateFileTool(cmd::ToolTag, root_path=nothing)
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args
    language, content = parse_code_block(cmd.content)
    # Expand the path during tool creation, similar to CatFileTool
    file_path = expand_path(file_path, root_path === nothing ? get(cmd.kwargs, "root_path", "") : root_path)
    CreateFileTool(; language, file_path, content)
end

instantiate(::Val{Symbol(CREATE_FILE_TAG)}, cmd::ToolTag) = CreateFileTool(cmd)
toolname(cmd::Type{CreateFileTool}) = CREATE_FILE_TAG
get_description(cmd::Type{CreateFileTool}) = """
To create new file you can use "$(CREATE_FILE_TAG)" tag with file_path like this:
$(CREATE_FILE_TAG) path/to/file
$(code_format("new_file_content", "language"))

It is important you ALWAYS close with "```$(END_OF_CODE_BLOCK) after the code block!".
"""
stop_sequence(cmd::Type{CreateFileTool}) = ""

function execute(tool::CreateFileTool; no_confirm=false)
    # Path is already expanded during tool creation
    path = tool.file_path
    
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
    # Escape square brackets and parentheses for shell
    escaped_path = replace(file_path, r"[\[\]()]" => s"\\\0")
    "cat > $(escaped_path) <<'$delimiter'\n$(content)\n$delimiter"
end
