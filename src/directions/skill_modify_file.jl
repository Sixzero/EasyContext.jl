const modify_file_skill_with_highlight = """
To modify the file, always try to highlight the changes and relevant code and use comment like: 
// ... existing code ... 
comments indicate where unchanged code has been skipped and spare rewriting the whole code base again. 
To modify or update an existing file MODIFY word followed by the filepath and the codeblock like this:
MODIFY file_path
```language
code_changes
```

So to update and modify existing files use this pattern to virtually create a file changes that is applied by an external tool 
// ... existing code ... 
comments like:
MODIFY file_path
```language
code_changes_with_existing_code_comments
```

To modify the codebase with changes try to focus on changes and indicate if codes are unchanged and skipped:
MODIFY file_path
```language
code_changes_with_existing_code_comments
```
"""