
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
    if length(original_content) > 10_000
        @show "WE DO REPLACE"
        ai_generated_content = apply_modify_by_replace(original_content, cb.content)
    else
        ai_generated_content = apply_modify_by_llm(original_content, cb.content)
    end
    
    original_content, ai_generated_content
end

function apply_modify_by_diff(original_content::AbstractString, changes_content::AbstractString; models=["gem15f", "claudeh", "claude"], temperature=0, verbose=false)
    # Add line numbers to original content
    numbered_content = join(["$(lpad(i, 4, ' ')) $(line)" for (i, line) in enumerate(split(original_content, '\n'))], '\n')
    println(numbered_content[end-500:end])
    
    prompt = """You are a diff generator specialized in creating high-level, semantically coherent unified diffs.
    Wrap your response in <diff> tags and only output the diff in a simplified unified diff format.
    
    Important Guidelines:
    1. Use a simplified unified diff format that omits line numbers - just use @@ ... @@ as separator
    2. Focus on complete, coherent code blocks (functions, methods, classes) rather than individual lines
    3. Include enough context (1-2 lines) around changes to ensure proper placement
    4. Use "-" for removed lines and "+" for added lines
    5. If Proposed changes doesn't specify location, place it at the end or where most appropriate
    6. Only include necessary changes, don't modify unrelated parts
    7. Try to keep the changes in larger, semantically meaningful chunks rather than scattered line edits
    8. Make sure to include all relevant code - don't use ellipsis or lazy comments

    Note: The original content below includes line numbers at the start of each line (first 5 characters).
    These line numbers are only for reference - your diff should ignore them and work with the actual content.
    
    Original content:
    ```
    $(numbered_content)
    ```

    Proposed changes:
    ```
    $(changes_content)
    ```

    Provide your response between <diff> tags in this format:
    <diff>
    @@ ... @@
    [unchanged context line]
    -[removed line]
    -[removed line]
    +[added line]
    +[added line]
    [unchanged context line]
    </diff>"""

    last_error = nothing
    for (i, model) in enumerate(models)
        try
            verbose && println("\e[38;5;240mGenerating diff with AI ($model)...\e[0m")
            aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
            println(uppercase(model))
            println(aigenerated.content)
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
        
        # Try with different patch options for more flexibility
        for options in [
            "-u",                    # standard unified diff
            "-u -l",                 # ignore whitespace
            "-u -f",                 # force, less strict matching
            "-u -l -f",             # combine ignore whitespace and force
            "-u --ignore-whitespace" # most lenient whitespace handling
        ]
            try
                output = read(`patch $options $original_file $diff_file`, String)
                # If we got here, patch succeeded
                return read(original_file, String)
            catch e
                # Continue to next option if this one failed
                continue
            end
        end
        
        # If all patch attempts failed, throw error
        throw(ErrorException("Failed to apply patch with all flexibility options"))
    end
end

function apply_modify_by_replace(original_content::AbstractString, changes_content::AbstractString; models=["gem15f", "claude"], temperature=0, verbose=false)
    best_result = original_content
    min_missing = typemax(Int)

    prompt = """You are a pattern matching specialist. Generate a list of search and replace pairs that will transform the original content to match the proposed changes.
    Wrap your response in <replacements> tags and provide match/replacewith pairs.
    
    
    Important Guidelines:
    1. Each pattern should be unique enough to match exactly what needs to be changed
    2. Include enough context in patterns to ensure correct placement
    3. Use complete code blocks when possible
    4. If changes don't specify location, create patterns that would add at the most appropriate place
    5. Only include necessary changes
    6. Make sure patterns are specific and won't cause unintended matches
    7. Do not escape any characters - provide the exact text to match and replace
    8. Only escape \$ in string literals if needed for string interpolation

    
    Original content:
    ```
    $original_content
    ```
    
    Proposed changes:
    ```
    $changes_content
    ```
    
    Provide your response as match/replacewith pairs between <replacements> tags like this:
    <replacements>
    <match>
    function to_find(exact::Code)
        # with enough context
    </match>
    <replacewith>
    function replaced_with(new::Code)
        # new implementation
    </replacewith>

    <match>pattern2</match>
    <replacewith>replacement2</replacewith>
    </replacements>"""

    for (i, model) in enumerate(models)
        try
            verbose && println("\e[38;5;240mGenerating replacement patterns with AI ($model)...\e[0m")
            aigenerated = PromptingTools.aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
            replacements = extract_tagged_content(aigenerated.content, "replacements")
            result, missing_count = apply_replacements(original_content, replacements)
            
            if missing_count < min_missing
                best_result = result
                min_missing = missing_count
                missing_count == 0 && return best_result # Perfect match found
            end
        catch e
            i < length(models) && verbose && @warn "Failed with model $model, retrying with $(models[i+1])" exception=e
        end
    end
    return best_result # Return best attempt
end

function apply_replacements(content::AbstractString, replacements::AbstractString)
    modified_content = content
    matches = extract_all_tagged_pairs(replacements)
    
    # Check missing patterns
    missing_patterns = [pattern for (pattern, _) in matches if !occursin(pattern, content)]
    !isempty(missing_patterns) && @warn "Some patterns not found!" patterns=missing_patterns
    
    # Apply all replacements anyway
    for (pattern, replacement) in matches
        modified_content = replace(modified_content, pattern => replacement)
    end
    
    return modified_content, length(missing_patterns)
end

function extract_all_tagged_pairs(content::AbstractString)
    pairs = Pair{String,String}[]
    
    # Find all match/replacewith pairs
    while true
        match_start = findnext("<match>", content, 1)
        isnothing(match_start) && break
        
        match_end = findnext("</match>", content, match_start.stop)
        replace_start = findnext("<replacewith>", content, match_end.stop)
        replace_end = findnext("</replacewith>", content, replace_start.stop)
        
        isnothing(match_end) || isnothing(replace_start) || isnothing(replace_end) && break
        
        
        # Get content between tags and trim only leading/trailing whitespace
        pattern = strip(content[match_start.stop+1:match_end.start-1])
        replacement = strip(content[replace_start.stop+1:replace_end.start-1])
        
        push!(pairs, pattern => replacement)
        content = content[replace_end.stop+1:end]
    end
    
    return pairs
end



