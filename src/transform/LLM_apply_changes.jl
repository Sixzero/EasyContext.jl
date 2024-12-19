
using PromptingTools
using Random
using Base.Threads: @spawn

include("instant_apply_logger.jl")
include("apply_changes_prompts.jl")

function LLM_conditional_apply_changes(cb::ModifyFileCommand)
    original_content, ai_generated_content = LLM_apply_changes_to_file(cb)
    cb.postcontent = ai_generated_content
    cb
end

function LLM_apply_changes_to_file(cb::ModifyFileCommand)
    original_content = ""
    cd(cb.root_path) do
        if isfile(cb.file_path)
            file_path, line_range = parse_source(cb.file_path)
            original_content = read(file_path, String)
        else
            @warn "WARNING! Unexisting file! $(cb.file_path) pwd: $(pwd())"
            cb.content
        end
    end
    isempty(original_content) && return cb.content, cb.content
    
    # Check file size and choose appropriate method
    if length(original_content) > 10_000
        ai_generated_content = apply_modify_by_replace(original_content, cb.content)
    else
        ai_generated_content = apply_modify_by_llm(original_content, cb.content)
    end
    
    original_content, ai_generated_content
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

# replace_models = ["gpt4om", "gem15f"]
# replace_models = ["tqwen25b72"]
function apply_modify_by_replace(original_content::AbstractString, changes_content::AbstractString; models=["gem15f", "tqwen25b72", "gpt4om", ], temperature=0, verbose=false)
    best_result = original_content
    min_missing = typemax(Int)
    prompt = get_replace_prompt(original_content, changes_content)

    for (i, model) in enumerate(models)
        try
            verbose && println("\e[38;5;240mGenerating replacement patterns with AI ($model)...\e[0m")
            aigenerated = aigenerate(prompt, model=model, api_kwargs=(; temperature), verbose=false)
            replacements = extract_tagged_content(aigenerated.content, "REPLACEMENTS")
            matches = extract_all_tagged_pairs(replacements)

            result, missing_count = apply_replacements(original_content, matches)
            
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

function apply_replacements(content::AbstractString, matches::Vector{Pair{String,String}})
    modified_content = content
    
    # Check missing patterns
    missing_patterns = [pattern for (pattern, _) in matches if !occursin(pattern, content)]
    !isempty(missing_patterns) && @warn "Some patterns not found!" patterns=missing_patterns
    for miss in missing_patterns
        println("MISSING:\n$miss")
    end
    
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



