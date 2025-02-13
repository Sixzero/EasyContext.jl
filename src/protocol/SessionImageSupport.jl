const IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "bmp"]

# Different path patterns
"""
Pattern for matching image paths within quotes (both single and double quotes).
Supports any valid path format as long as it ends with supported image extension.
"""
const QUOTED_PATH_PATTERN = r"[\"']([^\"']+?\.(?:%EXT%))[\"']"

"""
Pattern for matching unquoted image paths.
Only matches absolute paths starting with '/' followed by path components ending with supported image extension.
Must be a complete word (not part of another path).
"""
const UNQUOTED_PATH_PATTERN = r"(?:^|\s)(\/[^\n]+?\.(?:%EXT%))(?=\s|$)"

function build_pattern(extensions::Vector{String}, patterns::Vector{Regex})
    ext_pattern = join(extensions, "|")
    combined_patterns = [replace(pattern.pattern, "%EXT%" => ext_pattern) for pattern in patterns]
    Regex(join(combined_patterns, "|"))
end

is_image_path(word::AbstractString) = occursin(build_pattern(IMAGE_EXTENSIONS, [QUOTED_PATH_PATTERN]), word)

function extract_image_paths(content::AbstractString)
    pattern = build_pattern(IMAGE_EXTENSIONS, [QUOTED_PATH_PATTERN, UNQUOTED_PATH_PATTERN])
    matches = eachmatch(pattern, content)
    String[first(filter(!isnothing, m.captures)) for m in matches]
end

function validate_image_paths(paths::Vector{String})
    valid_paths = String[]
    for p in paths
        if isfile(p)
            push!(valid_paths, p)
        else
            @warn "Image file not found: $p"
        end
    end
    valid_paths
end