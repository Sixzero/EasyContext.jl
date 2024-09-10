using AISH: get_project_files, format_file_content
using PromptingTools.Experimental.RAGTools
import AISH

abstract type AbstractContextProcessor end

# Include ContextNode definition
include("ContextNode.jl")
# Include other context processors
include("CodebaseUtils.jl")
include("EmbedderUtils.jl")
include("EmbeddingContext.jl")
include("CodebaseContext.jl")
include("CodebaseContextV2.jl")
include("ShellContext.jl")
include("JuliaPackageContext.jl")
include("PythonPackageContext.jl")
include("GoogleContext.jl")

# Utility functions for context processors
function print_context_updates(new_items::Vector{String}, updated_items::Vector{String}, unchanged_items::Vector{String}; item_type::String="files")
    printstyled("Number of $item_type selected: ", color=:green, bold=true)
    printstyled(length(new_items) + length(updated_items) + length(unchanged_items), "\n", color=:green)
    
    for item in new_items
        printstyled("  [NEW] $item\n", color=:blue)
    end
    for item in updated_items
        printstyled("  [UPDATED] $item\n", color=:yellow)
    end
    for item in unchanged_items
        printstyled("  [UNCHANGED] $item\n", color=:light_black)
    end
end

function process_selected_files(processor, selected_files)
    new_files = String[]
    updated_files = String[]
    unchanged_files = String[]
    new_contents = String[]
    updated_contents = String[]
    
    # First, check all tracked files for updates
    for (file, (_, old_content)) in processor.tracked_files
        current_content = format_file_content(file)
        if old_content != current_content
            push!(updated_files, file)
            push!(updated_contents, current_content)
            processor.tracked_files[file] = (processor.call_counter, current_content)
        end
    end
    
    # Then, process selected files
    for file in selected_files
        if !haskey(processor.tracked_files, file)
            formatted_content = format_file_content(file)
            push!(new_files, file)
            push!(new_contents, formatted_content)
            processor.tracked_files[file] = (processor.call_counter, formatted_content)
        elseif file ∉ updated_files
            push!(unchanged_files, file)
        end
    end
    
    return new_files, updated_files, unchanged_files, new_contents, updated_contents
end

get_chunk_standard_format(source, content) = "# $source\n$content" 