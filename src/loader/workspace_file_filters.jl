
const comment_map = Dict{String, Tuple{String,String}}(
        ".jl" => ("#", ""), ".py" => ("#", ""), ".sh" => ("#", ""), ".bash" => ("#", ""), ".zsh" => ("#", ""), ".r" => ("#", ""), ".rb" => ("#", ""),
        ".js" => ("//", ""), ".ts" => ("//", ""), ".cpp" => ("//", ""), ".c" => ("//", ""), ".java" => ("//", ""), ".cs" => ("//", ""), ".php" => ("//", ""), ".go" => ("//", ""), ".rust" => ("//", ""), ".swift" => ("//", ""),
        ".html" => ("<!--", "-->"), ".xml" => ("<!--", "-->")
)

# Optimized version - directly check if extension is in the set
function is_project_file(lowered_file, PROJECT_FILES, FILE_EXTENSIONS)
    # Check if file is directly in project files
    lowered_file in PROJECT_FILES && return true
    
    # Extract file extension and check if it's in the allowed extensions set
    parts = split(lowered_file, '.')
    if length(parts) > 1
        ext = parts[end]
        return ext in FILE_EXTENSIONS
    end
    
    return false
end

# More precise file ignoring
function ignore_file(file, IGNORED_FILE_PATTERNS)
    basename_file = basename(file)
    for pattern in IGNORED_FILE_PATTERNS
        # If pattern has a path separator, match against full path
        if occursin("/", pattern)
            endswith(file, pattern) && return true
        else
            # Otherwise just match against basename
            endswith(basename_file, pattern) && return true
        end
    end
    return false
end

struct GitIgnorePattern
    regex::Regex
    is_negation::Bool
end
struct GitIgnoreFile
    path::String
    patterns::Vector{GitIgnorePattern}
end

function gitignore_to_regex(pattern::AbstractString)::Union{GitIgnorePattern,Nothing}
    pattern = strip(pattern)
    isempty(pattern) && return nothing  # Return nothing for empty patterns
    startswith(pattern, "#") && return nothing  # Skip comments

    # Handle negation patterns
    is_negation = startswith(pattern, "!")
    pattern = is_negation ? pattern[2:end] : pattern

    if pattern == "**"
        return GitIgnorePattern(r".*", is_negation)
    end
    
    # Handle directory patterns ending with slash
    ends_with_slash = endswith(pattern, "/")
    pattern = ends_with_slash ? pattern[1:end-1] : pattern
    
    # Handle patterns with leading slash - these should only match at the root level
    has_leading_slash = startswith(pattern, "/")
    if has_leading_slash
        pattern = pattern[2:end]  # Remove the leading slash
    end
    
    # Escape special regex characters except those with special meaning in gitignore
    regex = replace(pattern, r"([.$+(){}\[\]\\^|])" => s"\\\1")  # Escape special regex characters
    
    # Handle gitignore pattern syntax (order matters!)
    regex = replace(regex, r"\?" => ".")          # ? matches any single character
    regex = replace(regex, r"\*\*/" => "(.*/)?")  # **/ matches any directory depth
    regex = replace(regex, r"\*\*" => ".*")       # ** matches any characters
    regex = replace(regex, r"\*" => "[^/]*")      # * matches any characters except /
    
    # If pattern has a leading slash, it should only match at the root level
    if has_leading_slash
        regex = "^" * regex
    else
        # Without leading slash, it can match anywhere in the path
        regex = "(^|/)" * regex
    end
    
    # If pattern ends with slash, it should match directories with content
    if ends_with_slash
        # Only match directories that have at least one file/directory inside them
        regex = regex * "/.*"
    end
    
    # Make sure all patterns match to the end of the string
    regex = regex * "\$"
    
    return GitIgnorePattern(Regex(regex), is_negation)
end

# Add a cache for parsed gitignore files
mutable struct GitIgnoreCache
    patterns_by_dir::Dict{String, GitIgnoreFile}
    GitIgnoreCache() = new(Dict{String, GitIgnoreFile}())
end

function parse_ignore_files(folder_path::AbstractString, IGNORE_FILES::Vector{String}, cache::GitIgnoreCache)::Union{GitIgnoreFile,Nothing}
    # Check if we've already parsed this directory
    haskey(cache.patterns_by_dir, folder_path) && return cache.patterns_by_dir[folder_path]

    raw_patterns = String[]
    for ignore_file in IGNORE_FILES
        ignore_path = joinpath(folder_path, ignore_file)
        if isfile(ignore_path)
            append!(raw_patterns, readlines(ignore_path))
        end
    end
    isempty(raw_patterns) && return nothing
    
    # Compile patterns once
    compiled_patterns = Vector{GitIgnorePattern}()
    for pattern in raw_patterns
        compiled = gitignore_to_regex(pattern)
        if compiled !== nothing
            push!(compiled_patterns, compiled)
        end
    end
    
    # Cache the result
    cache.patterns_by_dir[folder_path] = GitIgnoreFile(folder_path, compiled_patterns)
    return cache.patterns_by_dir[folder_path]
end

# Get accumulated patterns with caching
function get_accumulated_ignore_patterns(current_dir::AbstractString, root_path::AbstractString, 
                                        IGNORE_FILES::Vector{String}, cache::GitIgnoreCache)::Vector{GitIgnoreFile}
    # Build path chain from root to current directory
    path_chain = String[]
    temp_dir = current_dir
    
    # Create the directory chain from root_path to current_dir
    while startswith(temp_dir, root_path)
        push!(path_chain, temp_dir)
        temp_dir == root_path && break
        temp_dir = dirname(temp_dir)
    end
    
    # Process directories from root to current (for proper precedence)
    accumulated_patterns = Vector{GitIgnoreFile}()
    for dir in reverse(path_chain)
        # Parse and add patterns from this directory
        dir_patterns = parse_ignore_files(dir, IGNORE_FILES, cache)
        !isnothing(dir_patterns) && push!(accumulated_patterns, dir_patterns)
    end
    
    return accumulated_patterns
end

function is_ignored_by_patterns(
    file::AbstractString, 
    ignore_files::Vector{GitIgnoreFile}, 
)::Bool
    for ignore_file in ignore_files
        is_ignored_by_patterns(file, ignore_file.patterns, ignore_file.path) && return true
    end
    return false
end
function is_ignored_by_patterns(
    file::AbstractString, 
    ignore_patterns::Vector{GitIgnorePattern}, 
    root::AbstractString
)::Bool
    root == "" && return false
    isempty(ignore_patterns) && return false

    rel_path = relpath(file, root)
    should_ignore = false
    
    # Process all patterns in order - last matching pattern wins
    for pattern in ignore_patterns
        # Check if the pattern matches the file
        if occursin(pattern.regex, rel_path)
            # Update the ignore status based on this pattern
            # If negation (!pattern), it's explicitly included
            # Otherwise, it's ignored
            should_ignore = !pattern.is_negation
        end
    end

    return should_ignore
end

