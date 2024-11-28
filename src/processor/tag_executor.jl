
using EasyContext: CodeBlock

function extract_language(content::String)
    # Look for ```language pattern at the start
    m = match(r"^```(\w+)", content)
    if m !== nothing
        lang = m.captures[1]
        # Remove the ```language and closing ``` from content
        content = replace(content, r"^```\w+\n|\n```$"m => "")
        return lang, content
    end
    return "sh", content  # default to sh if no language specified
end

function tag2codeblock(tag::Tag)
    language, content = extract_language(tag.content)
    
    if tag.name == "MODIFY"
        file_path = first(tag.args)
        CodeBlock(
            type = :MODIFY,
            language = language,
            file_path = file_path,
            content = content,
            kwargs = tag.kwargs
        )
    elseif tag.name == "CREATE"
        file_path = first(tag.args)
        CodeBlock(
            type = :CREATE,
            language = language,
            file_path = file_path,
            content = content,
            kwargs = tag.kwargs,
        )
    else
        CodeBlock(
            type = :SHELL,
            language = language,
            content = content,
            kwargs = tag.kwargs
        )
    end
end

function execute_tag(tag::Tag; no_confirm=false)
    codeblock = tag2codeblock(tag)
    # Use the existing CodeBlock execution infrastructure
    execute_codeblock(codeblock; no_confirm)
end

