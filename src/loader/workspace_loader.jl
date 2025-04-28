using FilePathsBase

const path_separator="/"
include("resolution_methods.jl")

abstract type AbstractWorkspace end

@kwdef mutable struct Workspace <: AbstractWorkspace
    project_paths::Vector{String}
    rel_project_paths::Vector{String}=String[]
    root_path::String=""  # Changed from common_path to root_path
    resolution_method::AbstractResolutionMethod=FirstAsRootResolution()
    original_dir::String
    PROJECT_FILES::Set{String} = Set{String}([
        "Dockerfile", "docker-compose.yml", "Makefile", "LICENSE", "package.json", 
        "app.json", ".gitignore", "Gemfile", "Cargo.toml", ".eslintrc.json", 
        "requirements.txt", "requirements", "tsconfig.json", ".env.example" # , "Project.toml"
    ])
    FILE_EXTENSIONS::Set{String} = Set{String}([
        "toml", "ini", "cfg", "conf", "sh", "bash", "zsh", "fish",
        "html", "css", "scss", "sass", "less", "js", "cjs", "jsx", "ts", "tsx", "php", "vue", "svelte",
        "py", "pyw", "ipynb", "rb", "rake", "gemspec", "java", "kt", "kts", "groovy", "scala",
        "clj", "c", "h", "cpp", "hpp", "cc", "cxx", "cs", "csx", "go", "rs", "swift", "m", "mm",
        "pl", "pm", "lua", "hs", "lhs", "erl", "hrl", "ex", "exs", "lisp", "lsp", "l", "cl",
        "fasl", "jl", "r", "R", "Rmd", "mat", "asm", "s", "dart", "sql", "md", "mdx", "markdown",
        "rst", "adoc", "tex", "sty", "gradle", "sbt", "xml", "properties", "plist",
        "proto", "proto3", "graphql", "prisma", "yml", "yaml", "svg",
        "code-workspace", "txt"
    ])
    NONVERBOSE_FILTERED_EXTENSIONS::Set{String} = Set{String}([
        "jld2", "png", "jpg", "jpeg", "ico", "gif", "pdf", "zip", "tar", "tgz", "lock", "gz", "bz2", "xz",
        "doc", "docx", "ppt", "pptx", "xls", "xlsx", "csv", "tsv", "db", "sqlite", "sqlite3",
        "mp3", "mp4", "wav", "avi", "mov", "mkv", "webm", "ttf", "otf", "woff", "woff2", "eot",
        "lock", "arrow"
    ])
    FILTERED_FOLDERS::Set{String} = Set{String}([
        "build", "dist", "benchmarks", "node_modules", "__pycache__", 
        "conversations", "archived", "archive", "test_cases", ".git" ,"playground", ".vscode", "aish_executable", ".idea"
    ])
    IGNORED_FILE_PATTERNS::Vector{String} = [
        ".log", "config.ini", "secrets.yaml", "Manifest.toml",  "package-lock.json", 
        ".aishignore",  ".env"
    ]
    IGNORE_FILES::Vector{String} = [".gitignore", ".aishignore"]
    show_tokens::Bool = false
end
Base.cd(f::Function, workspace::Workspace) = !isempty(workspace.root_path) ? cd(f, workspace.root_path) : f()
Base.isempty(workspace::Workspace) = isempty(workspace.rel_project_paths)

function Workspace(project_paths::Vector{<:AbstractString}; 
                    resolution_method::AbstractResolutionMethod=FirstAsRootResolution(), 
                    virtual_ws=nothing,
                    show_tokens=false,
                    verbose=true)

    paths = String.(project_paths)  # Convert to String
    !isnothing(virtual_ws) && push!(paths, virtual_ws.rel_path)
    # Check if all paths exist
    for path in paths
        @assert isdir(expanduser(path)) "Path does not exist or is not a directory: $path $paths"
    end
    
    root_path, rel_project_paths = resolve(resolution_method, paths)
    original_dir = pwd()
    workspace = Workspace(;project_paths=paths, rel_project_paths, root_path, resolution_method, original_dir, show_tokens)
    
    isempty(workspace.root_path) && return workspace

    if verbose
        println("Project path initialized: $(root_path)")
        workspace.root_path != "" && cd(workspace.root_path) do
            print_project_tree(workspace)
        end
    end

    return workspace
end
function RAG.get_chunks(chunker, ws::AbstractWorkspace)
    file_paths = get_project_files(ws)
    isempty(file_paths) && return Vector{eltype(typeof(chunker).parameters[1])}()
    paths = [Path(p) for p in file_paths]
    cd(ws) do
        RAG.get_chunks(chunker, paths)
    end
end

function get_project_files(w::Workspace)
    all_files = String[]
    for path in w.rel_project_paths
        append!(all_files, get_filtered_files_and_folders(w, path)[1])
    end
    return all_files
end

function get_filtered_files_and_folders(w::Workspace, path::String)
    project_files = String[]
    filtered_files = Set{String}()
    filtered_dirs  = Set{String}()
    filtered_unignored_files = Set{String}()

    # Create a cache for gitignore patterns
    gitignore_cache = GitIgnoreCache()
    cd(w) do
        for (root, dirs, files_in_dir) in walkdir(path, topdown=true, follow_symlinks=true)
            rel_root = relpath(root) # to remove ./ start of path

            # Get accumulated patterns with caching
            accumulated_ignore_patterns::Vector{GitIgnoreFile} = get_accumulated_ignore_patterns(
                root, path, w.IGNORE_FILES, gitignore_cache
            )

            # Handle filtered folders
            if any(d -> basename(rel_root) == d, w.FILTERED_FOLDERS)
                push!(filtered_dirs, root)
                empty!(dirs) # MUTABLE change to skip all folders of walkdir iteration!
                continue
            end

            # Process directories
            filter!(dirs) do d
                dir_path = joinpath(root, d)
                is_ignored = is_ignored_by_patterns(dir_path, accumulated_ignore_patterns)
                if is_ignored
                    push!(filtered_dirs, dir_path)
                    return false  # Remove from dirs
                end
                return true  # Keep in dirs
            end
            # Process files
            for file in files_in_dir
                file_path = joinpath(root, file)

                dir_path = dirname(file_path)
                dir_path in filtered_dirs && continue
                
                # First check if it's ignored, then check if it's a project file
                is_ignored = is_ignored_by_patterns(file_path, accumulated_ignore_patterns)
                
                if is_ignored ||
                ignore_file(file_path, w.IGNORED_FILE_PATTERNS) ||
                !is_project_file(lowercase(file), w.PROJECT_FILES, w.FILE_EXTENSIONS)

                    file_ext = lowercase(get_file_extension(file))
                    # If it's not in the nonverbose filtered extensions list and has an extension,
                    # track it for warning
                    if !isempty(file_ext) && 
                    !(file_ext in w.FILE_EXTENSIONS) && 
                    !(file_ext in w.NONVERBOSE_FILTERED_EXTENSIONS) &&
                    !any(pattern -> endswith(file, pattern), w.IGNORED_FILE_PATTERNS)
                        push!(filtered_unignored_files, file_path)
                    end
                    
                    push!(filtered_files, file_path)
                else
                    push!(project_files, file_path)
                end
            end
        end
    end

    # Show warning for filtered extensions not in the nonverbose list
    if !isempty(filtered_unignored_files)
        @warn "Filtered files might be important: $(join(filtered_unignored_files, ", "))"
    end

    return project_files, filtered_files, filtered_dirs
end

# Helper function to get file extension
function get_file_extension(filename::String)
    parts = split(filename, '.')
    return length(parts) > 1 ? parts[end] : ""
end

# set_project_path(w::Workspace) = cd_rootpath(w)
# set_project_path(w::Workspace, paths) = begin
#     w.root_path, w.rel_project_paths = resolve(w.resolution_method, paths)
#     set_project_path(w)
#     if verbose
#         print_project_tree(workspace)
#     end
# end

default_summary_callback(fullpath, full_file::String) = ""
get_project_name(p) = basename(endswith(p, "/.") ? p[1:end-2] : rstrip(p, '/'))

print_project_tree(w::Workspace; 
                    show_tokens::Bool=false, 
                    show_files::Bool=true, 
                    filewarning::Bool=true, 
                    summary_callback=default_summary_callback, 
                    do_print::Bool=true) = print_project_tree(w, w.rel_project_paths; show_tokens, show_files, filewarning, summary_callback, do_print)
print_project_tree(w::AbstractWorkspace, paths::Vector{String}; 
                    show_tokens::Bool=false, 
                    show_files::Bool=true, 
                    filewarning::Bool=true, 
                    summary_callback=default_summary_callback, 
                    do_print::Bool=true) = begin
    [print_project_tree(w, path; show_tokens, show_files, filewarning, summary_callback, do_print) for path in paths]
end

function print_project_tree(
    w::AbstractWorkspace, 
    path::String; 
    show_tokens::Bool = false, 
    show_files::Bool = true, 
    filewarning::Bool = true,
    summary_callback = default_summary_callback,
    do_print::Bool = true
)
    # Get filtered files and folders once
    project_files, filtered_files, filtered_folders = get_filtered_files_and_folders(w, path)
    
    # Create async tasks for summaries
    summary_tasks = Dict{String, Task}()
    
    # Generate header
    header = "Project [$(normpath(path))/]$(get_project_name(abspath(path)))"
    
    # Build tree structure from project_files directly
    tree_str = generate_tree_from_files(
        path,
        project_files;
        show_tokens = show_tokens,
        only_dirs = !show_files,
        filewarning = filewarning,
        summary_callback = summary_callback,
        summary_tasks = summary_tasks
    )
    
    isempty(tree_str) && (tree_str = "└── (no subfolder)")
    
    # Wait for all summaries to complete
    for (filepath, task) in summary_tasks
        summary = fetch(task)
        placeholder = "{{SUMMARY:$filepath}}"
        tree_str = replace(tree_str, placeholder => !isempty(summary) ? " - $summary" : "")
    end
    
    # Combine header and tree
    output = """$header
                $tree_str
                """
    
    # Print if do_print is true
    do_print && println(output)
    # Return the output text
    return output
end

# New function that builds a tree from a list of pre-filtered files
function generate_tree_from_files(
    root_path::String,
    files::Vector{String};
    show_tokens::Bool = false,
    only_dirs::Bool = false,
    filewarning::Bool = true,
    summary_callback = default_summary_callback,
    summary_tasks::Dict{String, Task} = Dict{String, Task}()
)
    # Create a tree structure
    tree = Dict{String, Any}()
    
    # First, build directory structure from files
    for file in files
        # Get path relative to root_path
        rel_path = relpath(file, root_path)
        parts = splitpath(rel_path)
        
        # Navigate to the right spot in the tree
        current = tree
        for i in 1:length(parts)-1
            dir = parts[i]
            if !haskey(current, dir)
                current[dir] = Dict{String, Any}()
            end
            current = current[dir]
        end
        
        # Add the file at the leaf
        if !only_dirs
            current[parts[end]] = file  # Store full path for later
        end
    end
    
    # Then generate the tree string
    io = IOBuffer()
    print_tree_structure(io, tree, "", root_path;
        show_tokens = show_tokens,
        filewarning = filewarning,
        summary_callback = summary_callback,
        summary_tasks = summary_tasks
    )
    
    return String(take!(io))
end

# Helper function to print the tree structure
function print_tree_structure(
    io::IO,
    node::Dict{String, Any},
    prefix::String,
    root_path::String;
    show_tokens::Bool = false,
    filewarning::Bool = true,
    summary_callback = nothing,
    summary_tasks::Dict{String, Task} = Dict{String, Task}()
)
    # Sort directories and files
    entries = sort(collect(keys(node)))
    dirs = [e for e in entries if isa(node[e], Dict)]
    files = [e for e in entries if !isa(node[e], Dict)]
    
    # Process files
    for (i, file) in enumerate(files)
        full_path = node[file]  # This is the full path we stored
        is_last = i == length(files) && isempty(dirs)
        symbol = is_last ? "└── " : "├── "
        
        # Print file info
        file_display = file
        content_summary = ""
        colored_size_str = ""
        
        try
            # Determine if we need to access the file at all
            need_file_access = show_tokens || filewarning || (summary_callback !== nothing && summary_callback !== default_summary_callback)
            
            if need_file_access
                # Get file size if needed for tokens or warnings
                if show_tokens || filewarning
                    size_chars = filesize(full_path)
                    
                    # Add file size if show_tokens is true
                    file_display *= show_tokens ? " ($(size_chars))" : ""
                    
                    # Format the size string for warnings
                    if filewarning && size_chars > 10_000
                        size_str = format_file_size(size_chars)
                        
                        # Apply coloring for large files
                        if size_chars > 20_000
                            color, reset = "\e[31m", "\e[0m"
                            colored_size_str = " $color($size_str)$reset"
                        else
                            colored_size_str = " ($size_str)"
                        end
                    end
                end
                
                # Only read the file content if we need summary
                if summary_callback !== nothing && summary_callback !== default_summary_callback
                    full_file = read(full_path, String)
                    summary_tasks[full_path] = @async summary_callback(full_path, full_file)
                    content_summary = "{{SUMMARY:$full_path}}"
                end
            end
            
            println(io, "$(prefix)$(symbol)$(file_display)$(colored_size_str)$(content_summary)")
        catch e
            if isa(e, Base.InvalidCharError{Char})
                println(io, "$(prefix)$(symbol)$(file) (binary or invalid UTF-8)")
            else
                rethrow(e)
            end
        end
    end
    
    # Process directories
    for (i, dir) in enumerate(dirs)
        is_last = i == length(dirs)
        symbol = is_last ? "└── " : "├── "
        next_prefix = prefix * (is_last ? "    " : "│   ")
        
        println(io, "$(prefix)$(symbol)$(dir)/")
        print_tree_structure(io, node[dir], next_prefix, root_path;
            show_tokens = show_tokens,
            filewarning = filewarning,
            summary_callback = summary_callback,
            summary_tasks = summary_tasks
        )
    end
end

format_file_size(size_chars) = size_chars < 1000 ? "$(size_chars) chars" : "$(round(size_chars / 1000, digits=2))k chars"

workspace_format_description_raw(ws::AbstractWorkspace)  = """
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, 
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags. 
Our workspace has a root path: $(ws.root_path)
The projects and their folders:
""" * join(print_project_tree(ws, show_files=true, summary_callback=default_summary_callback,  do_print=false), "\n")

workspace_format_description(ws::AbstractWorkspace)  = """
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, 
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags. 
Our workspace has a root path: $(ws.root_path)
The projects and their folders:
""" * join(print_project_tree(ws, show_files=true, summary_callback=LLM_summary,  do_print=true), "\n")
