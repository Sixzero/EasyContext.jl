const modify_file_skill_with_highlight = """
To modify the file, always try to highlight the changes and relevant cmd_code and use comment like: 
// ... existing cmd_code ... 
comments indicate where unchanged cmd_code has been skipped and spare rewriting the whole cmd_code base again. 
To modify or update an existing file $(MODIFY_FILE_TAG) word followed by the filepath and the codeblock like this:
<$(MODIFY_FILE_TAG) file_path>
```language
code_changes
```
</$(MODIFY_FILE_TAG)>

So to update and modify existing files use this pattern to virtually create a file changes that is then applied by an external tool comments like:
// ... existing cmd_code ... 

<$(MODIFY_FILE_TAG) path/to/file>
```language
code_changes_with_existing_code_comments
```
</$(MODIFY_FILE_TAG)>

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

@kwdef mutable struct ModifyFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
end
has_stop_sequence(cmd::ModifyFileCommand) = false

function ModifyFileCommand(cmd::Command)
    # Clean up file path by removing trailing '>'
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args
    
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
    cmd_code = process_modify_command(cmd.file_path, cmd.content, cmd.root_path)
    shortened_code = startswith(cmd_code, "curl") ? "curl diff..." : get_shortened_code(cmd_code, 1, 1)
    print_code(shortened_code)
    cmd_all_info_modify(`zsh -c $cmd_code`)
end

preprocess(cmd::ModifyFileCommand) = LLM_conditional_apply_changes(cmd)

function process_modify_command(file_path::String, content::String, root_path)
    delimiter = get_unique_eof(content)
    if CURRENT_EDITOR == VIMDIFF
        content_esced = replace(content, "'" => "\\'")
        "vimdiff $file_path <(echo -e '$content_esced')"
    elseif CURRENT_EDITOR == MELD_PRO
        if is_diff_service_available()
            port = get(ENV, "MELD_PORT", "3000")
            payload = Dict(
                "leftPath" => file_path,
                "rightContent" => content,
                "pwd" => root_path
            )
            json_str = JSON3.write(payload)
            json_str_for_shell = replace(json_str, "'" => "'\\''")
            """curl -X POST http://localhost:$port/diff -H "Content-Type: application/json" -d '$(json_str_for_shell)'"""
        else
            # fallback to meld
            "meld $file_path <(cat <<'$delimiter'\n$content\n$delimiter\n)"
        end
    else  # MELD
        "meld $file_path <(cat <<'$delimiter'\n$content\n$delimiter\n)"
    end
end