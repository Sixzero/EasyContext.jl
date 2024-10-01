

const IGNORE_FILES = [".gitignore", ".aishignore"]


is_project_file(w, lowered_file) = lowered_file in w.PROJECT_FILES || any(endswith(lowered_file, "." * ext) for ext in w.FILE_EXTENSIONS)
ignore_file(w, file) = any(endswith(file, pattern) for pattern in w.IGNORED_FILE_PATTERNS)

function parse_ignore_file(root, filename)
    ignore_path = joinpath(root, filename)
    !isfile(ignore_path) && return String[]
    patterns = String[]
    for line in eachline(ignore_path)
        line = strip(line)
        isempty(line) && continue
        startswith(line, '#') && continue
        push!(patterns, line)
    end
    return patterns
end

function parse_ignore_files(w, root)
    patterns = String[]
    for ignore_file in w.IGNORE_FILES
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

function get_project_files(w)
    all_files = String[]
    for path in w.rel_project_paths
        append!(all_files, get_project_files(w, path))
    end
    return all_files
end
function get_project_files(w, path::String)
    files = String[]
    ignore_cache = Dict{String, Vector{String}}()
    ignore_stack = Pair{String, Vector{String}}[]
    
    for (root, dirs, files_in_dir) in walkdir(path, topdown=true)
        any(d -> d in w.FILTERED_FOLDERS, splitpath(root)) && (empty!(dirs); continue)
        
        # Read and cache ignore patterns for this directory
        if !haskey(ignore_cache, root)
            res = parse_ignore_files(w, root)
            if !isempty(res)
                ignore_cache[root] = res
                push!(ignore_stack, root => res)
            end
        end
        
        # Use the most recent ignore patterns
        ignore_patterns = isempty(ignore_stack) ? String[] : last(ignore_stack).second
        ignore_root = isempty(ignore_stack) ? "" : last(ignore_stack).first
        
        for file in files_in_dir
            file_path = joinpath(root, file)
            if is_project_file(w, lowercase(file)) && 
               !ignore_file(w, file_path) && 
               !is_ignored_by_patterns(file_path, ignore_patterns, ignore_root)
                push!(files, file_path)
            end
        end
        
        # Filter out ignored directories to prevent unnecessary recursion
        filter!(d -> !is_ignored_by_patterns(joinpath(root, d), ignore_patterns, ignore_root), dirs)
        
        # Remove ignore patterns from the stack when moving out of their directory
        while !isempty(ignore_stack) && !startswith(root, first(last(ignore_stack)))
            pop!(ignore_stack)
        end
    end
    return files
end
function get_all_project_files(path)
	all_files = get_project_files(path)
	result = map(file -> format_file_content(file), all_files)
	return join(result, "\n")
end



const comment_map = Dict{String, Tuple{String,String}}(
        ".jl" => ("#", ""), ".py" => ("#", ""), ".sh" => ("#", ""), ".bash" => ("#", ""), ".zsh" => ("#", ""), ".r" => ("#", ""), ".rb" => ("#", ""),
        ".js" => ("//", ""), ".ts" => ("//", ""), ".cpp" => ("//", ""), ".c" => ("//", ""), ".java" => ("//", ""), ".cs" => ("//", ""), ".php" => ("//", ""), ".go" => ("//", ""), ".rust" => ("//", ""), ".swift" => ("//", ""),
        ".html" => ("<!--", "-->"), ".xml" => ("<!--", "-->")
)


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

