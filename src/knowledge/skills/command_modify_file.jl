const modify_file_skill_with_highlight = """
To modify the file, always try to highlight the changes and relevant code and use comment like: 
// ... existing code ... 
comments indicate where unchanged code has been skipped and spare rewriting the whole code base again. 
To modify or update an existing file MODIFY word followed by the filepath and the codeblock like this:
<MODIFY file_path>
```language
code_changes
```
</MODIFY>

So to update and modify existing files use this pattern to virtually create a file changes that is then applied by an external tool comments like:
// ... existing code ... 

<MODIFY path/to/file>
```language
code_changes_with_existing_code_comments
```
</MODIFY #RUN>

To modify the codebase with changes try to focus on changes and indicate if codes are unchanged and skipped:
<MODIFY file_path>
```language
code_changes_with_existing_code_comments
```
</MODIFY>
"""

const modify_file_skill = Skill(
    name="MODIFY",
    skill_description=modify_file_skill_with_highlight,
    stop_sequence=""
)

@kwdef struct ModifyFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "txt"
    file_path::String
    root_path::String
    content::String
    kwargs::Dict{String,String} = Dict{String,String}()
end

function ModifyFileCommand(cmd::Command)
    language, content = parse_code_block(cmd.content)
    ModifyFileCommand(language=language, file_path=first(cmd.args), content=content, kwargs=cmd.kwargs)
end


function execute(cmd::ModifyFileCommand; no_confirm=false)
    code = cmd.content
    shortened_code = startswith(code, "curl") ? "curl diff..." : get_shortened_code(code, 1, 1)
    print_code(shortened_code)
    cmd_all_info_modify(`zsh -c $code`)
end


