
using PromptingTools
using Random

include("instant_apply_logger.jl")
include("../prompts/prompt_instant_apply.jl")


function apply_modify_by_llm(original_content::AbstractString, changes_content::AbstractString; model::Vector{String}=["gem20f", "dscode", "tqwen25b72"], temperature=0, verbose=false, merge_prompt::Function)
    prompt = merge_prompt(original_content, changes_content)

    verbose && println("\e[38;5;240mProcessing diff with AI ($model) for higher quality...\e[0m")

    # Initialize AIGenerateFallback with model preferences
    ai_manager = AIGenerateFallback(models=model, readtimeout=30)
    aigenerated = try_generate(ai_manager, prompt; api_kwargs=(; temperature), verbose=false)
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

# replace_models = ["gpt4om", "gem15f"]
# replace_models = ["tqwen25b72"]
function apply_modify_by_replace(original_content::AbstractString, changes_content::AbstractString; models=["gem20f", "tqwen25b72", "gpt4om", ], temperature=0, verbose=false)
    best_result = original_content
    best_missing_patterns = String[]
    prompt = get_replace_prompt(original_content, changes_content)

    for (i, model) in enumerate(models)
        try
            verbose && println("\e[38;5;240mGenerating replacement patterns with AI ($model)...\e[0m")
            aigenerated = aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
            replacements = extract_tagged_content(aigenerated.content, "REPLACEMENTS")
            matches = extract_all_tagged_pairs(replacements)

            result, missing_patterns = apply_replacements(original_content, matches)

            if length(missing_patterns) < length(best_missing_patterns) || isempty(best_missing_patterns)
                best_result = result
                best_missing_patterns = missing_patterns
                isempty(missing_patterns) && return best_result # Perfect match found
            end
        catch e
            i < length(models) && verbose && @warn "Failed with model $model, retrying with $(models[i+1])" exception=e
        end
    end

    if !isempty(best_missing_patterns)
        @warn "Some patterns not found!" patterns=best_missing_patterns
        for miss in best_missing_patterns
            println("MISSING:\n$miss")
        end
    end
    return best_result
end

function apply_replacements(content::AbstractString, matches::Vector{Pair{String,String}})
    modified_content = content

    # Check missing patterns
    missing_patterns = [pattern for (pattern, _) in matches if !occursin(pattern, content)]

    # Apply all replacements anyway
    for (pattern, replacement) in matches
        modified_content = replace(modified_content, pattern => replacement)
    end

    return modified_content, missing_patterns
end

function extract_all_tagged_pairs(content::AbstractString)
    pairs = Pair{String,String}[]

    # Find all match/replacewith pairs
    while true
        match_start = findnext("<MATCH>", content, 1)
        isnothing(match_start) && break

        match_end = findnext("</MATCH>", content, match_start.stop)
        replace_start = findnext("<REPLACE>", content, match_end.stop)
        replace_end = findnext("</REPLACE>", content, replace_start.stop)

        isnothing(match_end) || isnothing(replace_start) || isnothing(replace_end) && break


        # Get content between tags and trim only leading/trailing whitespace
        pattern = strip(content[match_start.stop+1:match_end.start-1])
        replacement = strip(content[replace_start.stop+1:replace_end.start-1])

        push!(pairs, pattern => replacement)
        content = content[replace_end.stop+1:end]
    end

    return pairs
end
