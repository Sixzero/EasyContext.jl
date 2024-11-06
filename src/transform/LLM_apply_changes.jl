
using PromptingTools
using Random
using Base.Threads: @spawn

include("instant_apply_logger.jl")
include("apply_changes_prompts.jl")

function LLM_conditonal_apply_changes(cb::CodeBlock, ws)
    cb.content = (if cb.type==:MODIFY
        original_content, ai_generated_content = LLM_apply_changes_to_file(cb, ws)
        ai_generated_content
    else
        cb.pre_content
    end)
    cb
end

function LLM_apply_changes_to_file(cb::CodeBlock, ws)
    local original_content
    cd(ws.root_path) do
        !isfile(cb.file_path) && @warn "UNEXISTING file $(cb.file_path) pwd: $(pwd())"
        original_content = read(cb.file_path, String)
    end
    ai_generated_content = apply_changes_to_file(original_content, cb.pre_content)
    
    original_content, ai_generated_content
end

function apply_changes_to_file(original_content::AbstractString, changes_content::AbstractString; model::String="gpt4om", temperature=0, verbose=false, get_merge_prompt::Function=get_merge_prompt_v1)
    prompt = get_merge_prompt(original_content, changes_content)

    verbose && println("\e[38;5;240mProcessing diff with AI ($model) for higher quality...\e[0m")
    aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature))
    return extract_final_content(aigenerated.content)
end

function extract_final_content(content::AbstractString)
    start_index = findfirst("<final>", content)

    end_index = findlast("</final>", content)
    
    if !isnothing(start_index) && !isnothing(end_index)
        # Extract the content between the last pair of tags
        start_pos = start_index.stop + 1
        end_pos = end_index.start - 1
        return content[start_pos:end_pos]
    else
        # If tags are not found, return the original content
        @warn "Tags are not found."
        return content
    end
end
