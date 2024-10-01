


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
    if pattern == "**"
        return r".*"
    end
    regex = replace(pattern, r"[.$^]" => s"\\\0")  # Escape special regex characters
    regex = replace(regex, r"\*\*/" => "(.*/)?")
    regex = replace(regex, r"\*\*" => ".*")
    regex = replace(regex, r"\*" => "[^/]*")
    regex = replace(regex, r"\?" => ".")
    regex = "^" * regex * "\$"
    return Regex(regex)
end

function is_ignored_by_patterns(file, ignore_patterns, root)
    root=="" && return false
    rel_path = relpath(file, root)
    for pattern in ignore_patterns
        regex = gitignore_to_regex(pattern)
        if occursin(regex, rel_path) || occursin(regex, basename(rel_path))
            return true
        end
        if endswith(pattern, '/') && startswith(rel_path, pattern[1:end-1])
            return true
        end
    end
    return false
end



function format_file_content(file)
	content = read(file, String)
	relative_path = relpath(file, pwd())

	ext = lowercase(splitext(file)[2])
    comment_prefix, comment_suffix = get(comment_map, ext, ("#", ""))

	return """
	File: $(relative_path)
	```
	$content
	```
	"""
end

