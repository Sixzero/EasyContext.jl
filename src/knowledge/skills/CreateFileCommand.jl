const create_file_skill = Skill(
    name=CREATE_FILE_TAG,
    description="""
To create new file you can use "$(CREATE_FILE_TAG)" tag with file_path like this:
$(CREATE_FILE_TAG) path/to/file
$(code_format("new_file_content", "language"))
$(END_OF_BLOCK_TAG)
It is important you ALWAYS close the tag with "$(END_OF_BLOCK_TAG)".
""",
    stop_sequence=""
)

@kwdef struct CreateFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "txt"
    file_path::String
    root_path::String
    content::String
end
has_stop_sequence(cmd::CreateFileCommand) = false

function CreateFileCommand(cmd::Command)
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args
    language, content = parse_code_block(cmd.content)
    CreateFileCommand(
        language=language,
        file_path=file_path,
        root_path=get(cmd.kwargs, "root_path", ""),
        content=content
    )
end

function execute(cmd::CreateFileCommand; no_confirm=false)
    path = normpath(joinpath(cmd.root_path, cmd.file_path))
    cmd_code = process_create_command(path, cmd.content)
    shortened_code = get_shortened_code(cmd_code, 4, 2)
    print_code(shortened_code)
    
    dir = dirname(path)
    !isdir(dir) && mkpath(dir)
    
    if no_confirm || get_user_confirmation()
        print_output_header()
        cmd_all_info_modify(`zsh -c $cmd_code`)
    else
        "\nOperation cancelled by user."
    end
end

process_create_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
    "cat > $(file_path) <<'$delimiter'\n$(content)\n$delimiter"
end