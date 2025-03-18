
using PromptingTools
using Dates

export optimize_reranker, analyze_missing_targets

"""
    optimize_reranker(reranker_fn; model="gpt4o", save_results=true)

Wraps a reranker function to analyze performance and return ranked chunks.
If expected_targets are provided, analyzes why targets were missed and saves results.

# Arguments
- `reranker_fn`: Function with signature `(chunks, query; kwargs...) -> reranked_chunks`
- `model`: LLM model for analysis (default: "gpt4o")
- `save_results`: Save analysis to file if true

# Returns
- Function with signature `(chunks, query, expected_targets=nothing; kwargs...) -> reranked_chunks`
"""
function optimize_reranker(reranker_fn; model="gpt4o", save_results=true)
    return function(chunks, query, expected_targets=nothing; kwargs...)
        # Call the original reranker
        reranked_chunks = reranker_fn(chunks, query; kwargs...)
        
        # If expected targets provided, analyze missing ones
        if !isnothing(expected_targets)
            analyze_missing_targets(chunks, reranked_chunks, expected_targets, query, model, save_results)
        end
        
        return reranked_chunks
    end
end

"""
    analyze_missing_targets(all_chunks, reranked_chunks, expected_targets, query, model, save_results)

Analyzes why expected target file paths were missed by the reranker using LLM reasoning.

# Arguments
- `all_chunks`: All chunks before reranking
- `reranked_chunks`: Reranked chunks
- `expected_targets`: Expected file paths
- `query`: Query used for reranking
- `model`: LLM model for analysis
- `save_results`: Save results to file if true
"""
function analyze_missing_targets(all_chunks::Vector{T}, reranked_chunks::Vector{T}, 
                                expected_targets::Vector{String}, query::String, 
                                model::String, save_results::Bool=false) where T
    # Extract paths from reranked chunks
    reranked_paths = [chunk.source.path for chunk in reranked_chunks]
    
    # Find missing targets
    missing_targets = filter(t -> !any(p -> is_path_match(t, p), reranked_paths), expected_targets)
    
    # If no missing targets, we're done
    if isempty(missing_targets)
        println("✅ All targets retrieved!")
        return
    end
    
    # Report missing targets
    println("⚠️ Missed $(length(missing_targets)) target(s): ", join(missing_targets, ", "))
    
    @show [c.source.path for c in all_chunks]
    # Collect chunks for missing targets
    target_to_chunks = Dict{String, Vector{T}}()
    for target in missing_targets
        target_chunks = filter(c -> is_path_match(target, c.source.path), all_chunks)
        target_to_chunks[target] = target_chunks
    end
    
    # Get reasoning from LLM
    reasons = Dict{String, String}()
    
    @show missing_targets
    # First handle targets with no chunks
    for target in missing_targets
        if isempty(target_to_chunks[target])
            reasons[target] = "Not in original chunks"
        end
    end
    
    # Then get LLM reasoning for targets with chunks
    targets_with_chunks = [t for t in missing_targets if !isempty(target_to_chunks[t])]
    @show targets_with_chunks
    if !isempty(targets_with_chunks)
        target_reasons = llm_reasoning(reranked_chunks, target_to_chunks, targets_with_chunks, query, model)
        merge!(reasons, target_reasons)
    end
    for (target, reason) in reasons
        println("  - $target: $reason")
    end
    
    # Save analysis if requested
    save_results && save_analysis(query, missing_targets, reasons, reranked_chunks)
end

"""
    llm_reasoning(selected_chunks, target_to_chunks, missing_targets, query, model)

Generates LLM-based reasoning for why certain targets were missed using a structured prompt.
Returns a dictionary mapping target paths to reasons.
"""
function llm_reasoning(selected_chunks::Vector{T}, target_to_chunks::Dict{String, Vector{T}}, 
                      missing_targets::Vector{String}, query::String, model::String) where T
    # Create system prompt
    system_prompt = """
    # Task
    You are analyzing why specific files were missed by a reranker in a search system.
    
    # Instructions
    - Examine the query, selected chunks, and missed chunks
    - For each missed file, explain why it might not have been ranked highly enough
    - Provide concise explanations focusing on content relevance, keyword matching, and semantic connections
    - Compare missed files with selected chunks when relevant
    
    # Output Format
    Your response must be structured as follows:
    
    ## File: [filename1]
    [Your explanation for why this file was missed]
    
    ## File: [filename2]
    [Your explanation for why this file was missed]
    
    And so on for each missed file.
    """
    
    # Prepare selected chunks (limit to top 3 for brevity)
    selected_content = ""
    for (i, chunk) in enumerate(selected_chunks[1:min(3, length(selected_chunks))])
        path = chunk.source.path
        content = chunk.content
        selected_content *= "## Selected chunk #$i. Path: `$path`\n```\n$content\n```\n\n"
    end
    
    # Prepare missed chunks
    missed_content = ""
    for (i, target) in enumerate(missing_targets)
        chunks = target_to_chunks[target]
        if !isempty(chunks)
            # Combine content from all chunks for this target
            content = join([c.content for c in chunks], "\n---\n")
            missed_content *= "## Missed file #$i: `$target`\n```\n$content\n```\n\n"
        end
    end
    
    # Create user prompt with markdown formatting
    user_prompt = """
    # Query
    ```
    $query
    ```
    
    # Selected Chunks
    $selected_content
    
    # Missed Files
    $missed_content
    
    # Analysis Request
    For each missed file, explain why it might have been missed by the reranker despite being relevant to the query.
    """
    
    # Get reasoning from LLM using message-based approach
    messages = [
        SystemMessage(content=system_prompt),
        UserMessage(content=user_prompt)
    ]
    
    response = aigenerate(messages; model)
    println("Response:")
    display(response)
    content = response.content
    
    # Parse the response to extract reasons for each target
    reasons = Dict{String, String}()
    
    # Split by file headers
    sections = split(content, r"## File: ", keepempty=false)
    
    # If no sections found, try alternative format
    if length(sections) <= 1
        sections = split(content, r"## Missed file #\d+: ", keepempty=false)
    end
    
    # Process each section
    for section in sections
        # Skip empty sections
        isempty(strip(section)) && continue
        
        # Find which target this section refers to
        target_match = nothing
        for target in missing_targets
            # Try to match by filename or path
            if occursin(basename(target), section) || occursin(target, section)
                target_match = target
                break
            end
        end
        
        # If we found a matching target, extract the reason
        if !isnothing(target_match)
            # Remove the target/filename from the beginning of the section
            reason_text = replace(section, r"^[^\n]*\n" => "")
            reasons[target_match] = strip(reason_text)
        end
    end
    
    # For any targets we couldn't find in the response, provide a generic reason
    for target in missing_targets
        if !haskey(reasons, target)
            @warn "Target missed reasoning: $target"
            reasons[target] = "No specific explanation provided by the LLM"
        end
    end
    
    return reasons
end

"""
    save_analysis(query, missing_targets, reasons, selected_chunks)

Saves analysis results to a timestamped file.
"""
function save_analysis(query::String, missing_targets::Vector{String}, 
                      reasons::Dict{String, String}, selected_chunks::Vector{T}) where T
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filename = "/home/six/repo/EasyContext.jl/data/reranker_analysis_$timestamp.txt"
    
    open(filename, "w") do io
        write(io, "# Reranker Analysis\n\n")
        write(io, "## Query\n`$query`\n\n")
        
        write(io, "## Selected Chunks\n")
        for (i, chunk) in enumerate(selected_chunks[1:min(5, length(selected_chunks))])
            write(io, "$i. `$(chunk.source.path)`\n")
            write(io, "   ```\n   $(chunk.content[1:min(200, length(chunk.content))])\n   ```\n\n")
        end
        if length(selected_chunks) > 5
            write(io, "... and $(length(selected_chunks)-5) more\n\n")
        end
        
        write(io, "## Missed Targets\n")
        for (i, target) in enumerate(missing_targets)
            reason = get(reasons, target, "No reason provided")
            write(io, "$i. `$target`\n   - $reason\n\n")
        end
    end
    
    println("📝 Analysis saved to $filename")
end

"""
    is_path_match(path1, path2)

Checks if two paths likely refer to the same file.
"""
function is_path_match(path1::String, path2::String)
    p1 = normalize_path(path1); p2 = normalize_path(path2);
    return p1 == p2 || endswith(p1, "/" * basename(p2)) || endswith(p2, "/" * basename(p1))
end

"""
    normalize_path(path)

Normalizes a file path for comparison.
"""
function normalize_path(path::String)
    path = replace(startswith(path, "./") ? path[3:end] : path, "\\" => "/")
    return occursin(':', path) ? first(split(path, ':')) : (isempty(path) || startswith(path, "/") ? path : "/" * path)
end
