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
function collect_execution_results(execution_tasks; timeout::Float64=300.0)
    # Async map: wait for all tasks concurrently with timeout (worst case = timeout, not N*timeout)
    timed_tasks = [@async begin
        result = timedwait(timeout; pollint=0.5) do
            istaskdone(task)
        end
        if result == :timed_out
            @warn "Tool execution timed out after $(timeout)s, interrupting..."
            schedule(task, InterruptException(); error=true)
            return nothing
        end
        fetch(task)
    end for task in execution_tasks]

    result_strs = String[]
    result_imgs = String[]
    result_audios = String[]
    for tt in timed_tasks
        attachments = fetch(tt)
        isnothing(attachments) && continue
        for att in attachments
            uri = isnothing(att.id) ? "" : "todoforai://attachment/$(att.id)"
            if startswith(att.mimeType, "image/")
                # Ensure data URL format for LLM API (contentBase64 is raw base64, stripped by normalize_base64)
                img_data = startswith(att.contentBase64, "data:") ? att.contentBase64 : "data:$(att.mimeType);base64,$(att.contentBase64)"
                push!(result_imgs, img_data)
            elseif startswith(att.mimeType, "audio/")
                audio_data = startswith(att.contentBase64, "data:") ? att.contentBase64 : "data:$(att.mimeType);base64,$(att.contentBase64)"
                push!(result_audios, audio_data)
            else
                text = String(base64decode(att.contentBase64))
                !isempty(text) && push!(result_strs, format_source_text(att.originalName, text; uri))
            end
        end
    end
    (join(result_strs, "\n"), result_imgs, result_audios)
end
