
const create_file_skill = Skill(
    name="CREATE",
    skill_description="""
To create new file write CREATE followed by the file_path like this:
<CREATE file_path>
```language
new_file_content
```
</CREATE>
""",
    stop_sequence=""
)

@kwdef struct CreateFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "txt"
    file_path::String
    content::String
    kwargs::Dict{String,String} = Dict{String,String}()
end

function CreateFileCommand(cmd::Command)
    language, content = parse_code_block(cmd.content)
    CreateFileCommand(language=language, file_path=first(cmd.args), content=content, kwargs=cmd.kwargs)
end

function execute(cmd::CreateFileCommand; no_confirm=false)
    code = cmd.content
    shortened_code = startswith(code, "curl") ? "curl diff..." : get_shortened_code(code, 4, 2)
    print_code(shortened_code)
    
    dir = dirname(cmd.file_path)
    !isdir(dir) && mkpath(dir)
    
    if no_confirm || get_user_confirmation()
        print_output_header()
        cmd_all_info_modify(`zsh -c $code`)
    else
        "\nOperation cancelled by user."
    end
end

