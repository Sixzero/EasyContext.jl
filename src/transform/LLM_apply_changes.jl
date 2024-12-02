
using PromptingTools
using Random
using Base.Threads: @spawn

include("instant_apply_logger.jl")
include("apply_changes_prompts.jl")

# Helper for retrying functions with different models
function retry_with_models(f::Function, models::Vector{String}; verbose=false)
    last_error = nothing
    for (i, model) in enumerate(models)
        try
            return f(model)
        catch e
            last_error = e
            i < length(models) && verbose && @warn "Failed with model $model, retrying with $(models[i+1])" exception=e
        end
    end
    throw(last_error)  # Re-throw the last error if all attempts failed
end
function LLM_conditional_apply_changes(cb::ModifyFileCommand)
    original_content, ai_generated_content = LLM_apply_changes_to_file(cb)
    cb.postcontent = ai_generated_content
    cb
end

function LLM_apply_changes_to_file(cb::ModifyFileCommand)
    local original_content
    cd(cb.root_path) do
        !isfile(cb.file_path) && @warn "UNEXISTING file $(cb.file_path) pwd: $(pwd())"
        original_content = get_updated_content(cb.file_path)
    end
    
    # Check file size and choose appropriate method
    if length(original_content) > 20_000
        ai_generated_content = apply_modify_by_diff(original_content, cb.content)
    else
        ai_generated_content = apply_modify_by_llm(original_content, cb.content)
    end
    
    original_content, ai_generated_content
end

function apply_modify_by_diff(original_content::AbstractString, changes_content::AbstractString; models=["gem15f", "claude"], temperature=0, verbose=false)
    prompt = """You are a diff generator. Create a minimal unified diff patch for the proposed changes.
    Wrap your response in <diff> tags and only output the diff in standard unified diff format.
    The diff should:
    - Start with line information using @@ markers
    - Use - for removed lines and + for added lines
    - Include minimal context (1-2 lines) around changes
    - Only include necessary changes, don't modify unrelated parts

    Original content:
    ```
    $original_content
    ```

    Proposed changes:
    ```
    $changes_content
    ```

    Provide your response in this format:
    <diff>
    @@ ... @@
    your unified diff content here
    </diff>"""

    last_error = nothing
    for (i, model) in enumerate(models)
        try
            verbose && println("\e[38;5;240mGenerating diff with AI ($model)...\e[0m")
            aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
            diff_content = extract_tagged_content(aigenerated.content, "diff")
            return apply_patch(original_content, diff_content)
        catch e
            last_error = e
            i < length(models) && verbose && @warn "Failed with model $model, retrying with $(models[i+1])" exception=e
        end
    end
    throw(last_error)  # Re-throw the last error if all attempts failed
end

function apply_modify_by_llm(original_content::AbstractString, changes_content::AbstractString; model::String="gem15f", temperature=0, verbose=false, get_merge_prompt::Function=get_merge_prompt_v1)
    prompt = get_merge_prompt(original_content, changes_content)

    verbose && println("\e[38;5;240mProcessing diff with AI ($model) for higher quality...\e[0m")
    aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
    content = extract_tagged_content(aigenerated.content, "final")
    isnothing(content) && @warn "The model: $model failed to generate properly tagged content."
    # res, is_ok = extract_final_content(aigenerated.content)
    # !is_ok && @warn "The model: $model failed to generate the final content."
    return something(content, changes_content)
end

"""
    extract_tagged_content(content::AbstractString, tag::AbstractString) -> Union{String, Nothing}

Extract content between HTML-style tags. Returns Nothing if tags are not found or malformed.
Uses findlast for closing tag to ensure we get the last instance.
"""
function extract_tagged_content(content::AbstractString, tag::AbstractString)
    start_index = findfirst("<$tag>", content)
    end_index = findlast("</$tag>", content)
    
    if !isnothing(start_index) && !isnothing(end_index)
        start_pos = start_index.stop + 1
        end_pos = end_index.start - 1
        return content[start_pos:end_pos]
    end
    return nothing
end

function apply_patch(original_content::AbstractString, diff_content::AbstractString)
    # Create temporary files
    mktempdir() do dir
        original_file = joinpath(dir, "original")
        diff_file = joinpath(dir, "changes.diff")
        
        # Write files
        write(original_file, original_content)
        write(diff_file, diff_content)
        
        # Apply patch
        try
            output = read(`patch -u $original_file $diff_file`, String)
            return read(original_file, String)
        catch e
            throw(ErrorException("Failed to apply patch: $e"))
        end
    end
end
