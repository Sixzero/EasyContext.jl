
using PromptingTools
using Random
using Base.Threads: @spawn

include("instant_apply_logger.jl")
include("apply_changes_prompts.jl")

LLM_conditonal_apply_changes(ANYTHING) = ANYTHING
function LLM_conditonal_apply_changes(cb::ModifyFileCommand)
    cb.postcontent = (if cb.type==:MODIFY
        original_content, ai_generated_content = LLM_apply_changes_to_file(cb)
        ai_generated_content
    else
        cb.content
    end)
    cb
end

function LLM_apply_changes_to_file(cb::ModifyFileCommand)
    local original_content
    cd(cb.root_path) do
        !isfile(cb.file_path) && @warn "UNEXISTING file $(cb.file_path) pwd: $(pwd())"
        original_content = get_updated_content(cb.file_path)
    end
    ai_generated_content = apply_changes_to_file(original_content, cb.content)
    
    original_content, ai_generated_content
end

function apply_changes_to_file(original_content::AbstractString, changes_content::AbstractString; model::String="gem15f", temperature=0, verbose=false, get_merge_prompt::Function=get_merge_prompt_v1)
    prompt = get_merge_prompt(original_content, changes_content)

    verbose && println("\e[38;5;240mProcessing diff with AI ($model) for higher quality...\e[0m")
    aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
    res, is_ok = extract_final_content(aigenerated.content)
    !is_ok && @warn "The model: $model failed to generate the final content."
    return res
end

function extract_final_content(content::AbstractString)
    start_index = findfirst("<final>", content)

    end_index = findlast("</final>", content)
    
    if !isnothing(start_index) && !isnothing(end_index)
        # Extract the content between the last pair of tags
        start_pos = start_index.stop + 1
        end_pos = end_index.start - 1
        return content[start_pos:end_pos], true
    else
        # If tags are not found, return the original content
        @warn "Tags are not found."
        return content, false
    end
end
