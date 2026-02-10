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
Collect results from execution tasks that return (str, imgs, audios, name, uri) tuples or nothing.
Text results are wrapped with `format_source_text` (matching file attachment format).
Images and audio are kept separate for provider-specific typed inputs.
Returns (joined_str, all_imgs, all_audios).
"""
function collect_execution_results(execution_tasks)
    result_strs = String[]
    result_imgs = String[]
    result_audios = String[]
    for task in execution_tasks
        result = fetch(task)
        isnothing(result) && continue
        str, imgs, audios, name, uri = result
        !isempty(str) && push!(result_strs, format_source_text(name, str; uri))
        !isnothing(imgs) && append!(result_imgs, imgs)
        !isnothing(audios) && append!(result_audios, audios)
    end
    (join(result_strs, "\n"), result_imgs, result_audios)
end
