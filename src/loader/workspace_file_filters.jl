


const comment_map = Dict{String, Tuple{String,String}}(
        ".jl" => ("#", ""), ".py" => ("#", ""), ".sh" => ("#", ""), ".bash" => ("#", ""), ".zsh" => ("#", ""), ".r" => ("#", ""), ".rb" => ("#", ""),
        ".js" => ("//", ""), ".ts" => ("//", ""), ".cpp" => ("//", ""), ".c" => ("//", ""), ".java" => ("//", ""), ".cs" => ("//", ""), ".php" => ("//", ""), ".go" => ("//", ""), ".rust" => ("//", ""), ".swift" => ("//", ""),
        ".html" => ("<!--", "-->"), ".xml" => ("<!--", "-->")
)

is_project_file(lowered_file, PROJECT_FILES, FILE_EXTENSIONS) = lowered_file in PROJECT_FILES || any(endswith(lowered_file, "." * ext) for ext in FILE_EXTENSIONS)
ignore_file(file, IGNORED_FILE_PATTERNS) = any(endswith(file, pattern) for pattern in IGNORED_FILE_PATTERNS)

function parse_ignore_files(root, IGNORE_FILES)
    patterns = String[]
    for ignore_file in IGNORE_FILES
        ignore_path = joinpath(root, ignore_file)
        if isfile(ignore_path)
            append!(patterns, readlines(ignore_path))
        end
    end
    return patterns
end

function gitignore_to_regex(pattern)
    pattern = strip(pattern)
    isempty(pattern) && return (r"", false)
    startswith(pattern, "#") && return (r"", false)  # Skip comments

    # Handle negation patterns
    is_negation = startswith(pattern, "!")
    pattern = is_negation ? pattern[2:end] : pattern

    if pattern == "**"
        return (r".*", is_negation)
    end
    regex = replace(pattern, r"[.$^]" => s"\\\0")  # Escape special regex characters
    regex = replace(regex, r"\*\*/" => "(.*/)?")
    regex = replace(regex, r"\*\*" => ".*")
    regex = replace(regex, r"\*" => "[^/]*")
    regex = replace(regex, r"\?" => ".")
    regex = "^" * regex * "\$"
    return (Regex(regex), is_negation)
end

function is_ignored_by_patterns(file, ignore_patterns, root)
    root == "" && return false
    isempty(ignore_patterns) && return false

    rel_path = relpath(file, root)
    should_ignore = false
    explicit_include = false

    # First pass: check for explicit includes (negation patterns)
    for pattern in ignore_patterns
        isempty(pattern) && continue
        startswith(pattern, "#") && continue

        regex, is_negation = gitignore_to_regex(pattern)
        isempty(string(regex.pattern)) && continue

        if is_negation && (occursin(regex, rel_path) || occursin(regex, basename(rel_path)))
            explicit_include = true
            break
        end
    end

    # If explicitly included, don't ignore
    explicit_include && return false

    # Second pass: check for ignore patterns
    for pattern in ignore_patterns
        isempty(pattern) && continue
        startswith(pattern, "#") && continue

        regex, is_negation = gitignore_to_regex(pattern)
        isempty(string(regex.pattern)) && continue

        # Skip negation patterns in second pass
        is_negation && continue

        # Check if any parent directory matches the ignore pattern
        path_parts = splitpath(rel_path)
        for i in 1:length(path_parts)
            partial_path = join(path_parts[1:i], '/')
            if occursin(regex, partial_path)
                should_ignore = true
                break
            end
        end

        # Also check the full path
        if occursin(regex, rel_path) || occursin(regex, basename(rel_path))
            should_ignore = true
        end
    end

    return should_ignore
end



# function format_file_content(file)
# 	content = read(file, String)
# 	relative_path = relpath(file, pwd())

# 	ext = lowercase(splitext(file)[2])
#     comment_prefix, comment_suffix = get(comment_map, ext, ("#", ""))

# 	return """
# 	File: $(relative_path)
# 	```
# 	$content
# 	```
# 	"""
# end

