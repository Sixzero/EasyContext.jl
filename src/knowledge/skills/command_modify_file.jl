const modify_file_skill_with_highlight = """
To modify the file, always try to highlight the changes and relevant code and use comment like: 
// ... existing code ... 
comments indicate where unchanged code has been skipped and spare rewriting the whole code base again. 
To modify or update an existing file $(MODIFY_FILE_TAG) word followed by the filepath and the codeblock like this:
<$(MODIFY_FILE_TAG) file_path>
```language
code_changes
```
</$(MODIFY_FILE_TAG)>

So to update and modify existing files use this pattern to virtually create a file changes that is then applied by an external tool comments like:
// ... existing code ... 

<$(MODIFY_FILE_TAG) path/to/file>
```language
code_changes_with_existing_code_comments
```
</$(MODIFY_FILE_TAG) #RUN>

To modify the codebase with changes try to focus on changes and indicate if codes are unchanged and skipped:
<$(MODIFY_FILE_TAG) file_path>
```language
code_changes_with_existing_code_comments
```
</$(MODIFY_FILE_TAG)>
"""

const modify_file_skill = Skill(
    name=MODIFY_FILE_TAG,
    description=modify_file_skill_with_highlight,
    stop_sequence=""
)

@kwdef struct ModifyFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
end

function ModifyFileCommand(cmd::Command)
    # Clean up file path by removing trailing '>'
    file_path = endswith(cmd.args[1], ">") ? chop(cmd.args[1]) : cmd.args[1]
    
    language, content = parse_code_block(cmd.content)
    ModifyFileCommand(
        language=language,
        file_path=file_path,
        root_path=get(cmd.kwargs, "root_path", ""),
        content=content,
        postcontent=""
    )
end


function execute(cmd::ModifyFileCommand; no_confirm=false)
    code = cmd.content
    shortened_code = startswith(code, "curl") ? "curl diff..." : get_shortened_code(code, 1, 1)
    print_code(shortened_code)
    cmd_all_info_modify(`zsh -c $code`)
end


