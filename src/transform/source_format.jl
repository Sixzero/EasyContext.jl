using Base64

export format_source_text, collect_execution_results

"""
    format_source_text(name::String, content::String; uri::String="")::String

Canonical format for serializing named text content (file attachments, tool results, etc.)
into LLM message content. This is the single source of truth for the format.

Images and audio are NOT included here — they use provider-specific typed inputs.
"""
format_source_text(name::String, content::String; uri::String="")::String =
    isempty(uri) ? "# Source: $name\n$content" : "# Source: $name\n# URI: $uri\n$content"

"""
Collect results from execution tasks that return Vector{AttachmentWireCreate} or nothing.
Each attachment is categorized by mimeType:
- text/* → decode base64, wrap with `format_source_text` (with URI)
- image/* → keep base64 for provider-specific typed input
- audio/* → keep base64 for provider-specific typed input
Returns (joined_str, all_imgs, all_audios).
"""
function collect_execution_results(execution_tasks)
    result_strs = String[]
    result_imgs = String[]
    result_audios = String[]
    for task in execution_tasks
        attachments = fetch(task)
        isnothing(attachments) && continue
        for att in attachments
            uri = isnothing(att.id) ? "" : "todoforai://attachment/$(att.id)"
            if startswith(att.mimeType, "image/")
                push!(result_imgs, att.contentBase64)
            elseif startswith(att.mimeType, "audio/")
                push!(result_audios, att.contentBase64)
            else
                text = String(base64decode(att.contentBase64))
                !isempty(text) && push!(result_strs, format_source_text(att.originalName, text; uri))
            end
        end
    end
    (join(result_strs, "\n"), result_imgs, result_audios)
end
