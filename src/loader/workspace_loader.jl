const path_separator="/"
include("resolution_methods.jl")

@kwdef mutable struct Workspace
    project_paths::Vector{String}
    rel_project_paths::Vector{String}=String[]
    root_path::String=""  # Changed from common_path to root_path
    resolution_method::AbstractResolutionMethod=FirstAsRootResolution()
    original_dir::String
    PROJECT_FILES::Vector{String} = [
        "Dockerfile", "docker-compose.yml", "Makefile", "LICENSE", "package.json", 
        "README.md", 
        "Gemfile", "Cargo.toml"# , "Project.toml"
    ]
    FILE_EXTENSIONS::Vector{String} = [
        "toml", "ini", "cfg", "conf", "sh", "bash", "zsh", "fish",
        "html", "css", "scss", "sass", "less", "js", "jsx", "ts", "tsx", "php", "vue", "svelte",
        "py", "pyw", "ipynb", "rb", "rake", "gemspec", "java", "kt", "kts", "groovy", "scala",
        "clj", "c", "h", "cpp", "hpp", "cc", "cxx", "cs", "csx", "go", "rs", "swift", "m", "mm",
        "pl", "pm", "lua", "hs", "lhs", "erl", "hrl", "ex", "exs", "lisp", "lsp", "l", "cl",
        "fasl", "jl", "r", "R", "Rmd", "mat", "asm", "s", "dart", "sql", "md", "markdown",
        "rst", "adoc", "tex", "sty", "gradle", "sbt", "xml", 
        "proto", "proto3", "graphql", "prisma", "yml",
        "jld2",
        "so",
    ]
    FILTERED_FOLDERS::Vector{String} = [
        "build",
        "dist", "python", "benchmarks", "node_modules", 
        "conversations", "archived", "archive", "test_cases", ".git" ,"playground", ".vscode", "aish_executable"
    ]
    IGNORED_FILE_PATTERNS::Vector{String} = [
        ".log", "config.ini", "secrets.yaml", "Manifest.toml", ".gitignore", ".aiignore", ".aishignore",  # , "Project.toml", "README.md"
    ]
    IGNORE_FILES::Vector{String} = [
        ".gitignore", ".aishignore"
    ]
    show_tokens::Bool = false
end
Base.cd(f::Function, workspace::Workspace)        = !isempty(workspace.root_path)               ? cd(f, workspace.root_path)               : f()

# cd_rootpath(ws::Workspace) = begin
#     curr_rel_path  = [normpath(joinpath(pwd(),rel_path)) for rel_path in ws.rel_project_paths]
#     ideal_rel_path = [normpath(joinpath(root_path,rel_path)) for rel_path in ws.rel_project_paths]
#     new_rel_path = relpath.(ideal_rel_path, curr_rel_path)
#     cd(root_path)
#     println("Project path initialized: $(path)")

#     ws.rel_project_paths = new_rel_path
# end
function Workspace(project_paths::Vector{<:AbstractString}; 
                    resolution_method::AbstractResolutionMethod=FirstAsRootResolution(), 
                    virtual_ws=nothing,
                    show_tokens=false,
                    verbose=true)

    paths = String.(project_paths)  # Convert to String
    !isnothing(virtual_ws) && push!(paths, virtual_ws.rel_path)
    # Check if all paths exist
    for path in paths
        @assert isdir(expanduser(path)) "Path does not exist or is not a directory: $path"
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

(ws::Workspace)()::Vector{String} = return vcat(get_project_files(ws)...)
function (ws::Workspace)(chunker)
    chunks, sources = RAGTools.get_chunks(chunker, ws())
    return OrderedDict(zip(sources, chunks))
end

function get_project_files(w::Workspace)
    all_files = String[]
    cd(w) do
        for path in w.rel_project_paths
            append!(all_files, get_project_files(w, path))
        end
    end
    return all_files
end

function get_project_files(w::Workspace, path::String)
    files = String[]
    ignore_cache = Dict{String, Vector{String}}()
    ignore_stack = Pair{String, Vector{String}}[]
    
    for (root, dirs, files_in_dir) in walkdir(path, topdown=true, follow_symlinks=true)
        any(d -> d in w.FILTERED_FOLDERS, splitpath(root)) && (empty!(dirs); continue)
        
        # Read and cache ignore patterns for this directory
        if !haskey(ignore_cache, root)
            res = parse_ignore_files(root, w.IGNORE_FILES)
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
            if is_project_file(lowercase(file), w.PROJECT_FILES, w.FILE_EXTENSIONS) && 
               !ignore_file(file_path, w.IGNORED_FILE_PATTERNS) && 
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

# set_project_path(w::Workspace) = cd_rootpath(w)
# set_project_path(w::Workspace, paths) = begin
#     w.root_path, w.rel_project_paths = resolve(w.resolution_method, paths)
#     set_project_path(w)

#     if verbose
#         print_project_tree(workspace)
#     end

# end

default_summary_callback(full_file::String) = ""

print_project_tree(w::Workspace) = print_project_tree(w, w.rel_project_paths)
print_project_tree(w, paths::Vector{String}; show_tokens::Bool=false, show_files::Bool=true, filewarning::Bool=true, summary_callback::Function=default_summary_callback, do_print::Bool=true) = 
    [print_project_tree(w, path; show_tokens, show_files, filewarning, summary_callback, do_print) for path in paths]
function print_project_tree(
    w::Workspace, 
    path::String; 
    show_tokens::Bool=false, 
    show_files::Bool=true, 
    filewarning::Bool=true,
    summary_callback::Function=default_summary_callback,
    do_print::Bool=true
)
    cd(w) do
        # Generate header
        header = "Project [$(normpath(path))/]$(get_project_name(abspath(path)))"
        tree_str = generate_tree_string(
            path; 
            show_tokens=show_tokens, 
            only_dirs=!show_files, 
            filtered_folders=w.FILTERED_FOLDERS, 
            filewarning=filewarning,
            summary_callback=summary_callback
        )
        isempty(tree_str) && (tree_str = "└── (no subfolder)")
        # Combine header and tree
        output = """$header
                    $tree_str
                    """
        
        # Print if do_print is true
        do_print && println(output)
        # Return the output text
        return output
    end
end

get_project_name(p) = basename(endswith(p, "/.") ? p[1:end-2] : rstrip(p, '/'))


function generate_tree_string(
    path::String;
    show_tokens::Bool = false,
    only_dirs::Bool = false,
    filtered_folders::Vector{String} = String[],
    filewarning::Bool = true,
    summary_callback::Function = default_summary_callback
)
    io = IOBuffer()
    _print_tree(
        io,
        String[],
        path;
        show_tokens = show_tokens,
        only_dirs,
        filtered_folders = filtered_folders,
        filewarning = filewarning,
        summary_callback = summary_callback
    )
    return String(take!(io))
end

function _print_tree(io::IO, paths::Vector{String}, root_path::String=""; 
                     show_tokens::Bool=false, pre="", only_dirs::Bool=false, 
                     filtered_folders::Vector{String}=String(), filewarning::Bool=true, summary_callback::Function=default_summary_callback)
    # Read entries in the current directory
    entries = readdir(root_path)
    entries = filter(e -> !(e in filtered_folders || startswith(e, ".")), entries)
    dirs = sort([e for e in entries if isdir(joinpath(root_path, e))])
    files = sort([e for e in entries if isfile(joinpath(root_path, e))])

    # Count total entries to determine when to use "└──"
    total_entries = length(dirs) + (only_dirs ? 0 : length(files))
    if total_entries == 0
        return  # No entries to display
    end

    idx = 0
    # Print files if only_dirs is false
    if !only_dirs
        for file in files
            idx += 1
            is_last = idx == total_entries
            print_file(io, joinpath(root_path, file), is_last, pre; show_tokens=show_tokens, filewarning=filewarning, summary_callback=summary_callback)
        end
    end

    # Print directories
    for dir in dirs
        idx += 1
        is_last = idx == total_entries
        next_pre = pre * (is_last ? "    " : "│   ")
        println(io, pre * (is_last ? "└── " : "├── ") * dir * "/")
        # Recursively print subdirectories
        _print_tree(io, String[], joinpath(root_path, dir); 
                    show_tokens=show_tokens, pre=next_pre, only_dirs=only_dirs, 
                    filtered_folders=filtered_folders, filewarning=filewarning)
    end
end

function print_file(
    io::IO,
    full_path::String,
    is_last::Bool,
    pre::String = "";
    show_tokens::Bool = false,
    filewarning::Bool = true,
    summary_callback::Function = nothing
)
    symbol = is_last ? "└── " : "├── "
    name = basename(full_path)

    if isfile(full_path)
        size_chars = 0
        content_summary = ""

        try
            # Try reading the file as text
            full_file = read(full_path, String)
            size_chars = count(c -> !isspace(c), full_file)
            name *= show_tokens ? " ($(count_tokens(full_file)))" : ""

            # Call the summary callback if provided
            !isnothing(summary_callback) && (content_summary = summary_callback(full_file))
        catch e
            if isa(e, Base.InvalidCharError{Char})
                # If the file contains invalid UTF-8, treat it as binary
                size_chars = filesize(full_path)
                name *= " (binary or invalid UTF-8)"
            else
                # Handle other exceptions
                rethrow(e)
            end
        end

        # Format the size string
        size_str = ""
        if size_chars > 10_000
            size_str = format_file_size(size_chars)
        end

        # Apply coloring for large files if filewarning is true
        colored_size_str = ""
        if filewarning && size_chars > 20_000
            color, reset = "\e[31m", "\e[0m"
            colored_size_str = " $color($size_str)$reset"
        elseif size_str != ""
            colored_size_str = " ($size_str)"
        end

        # Append content summary if available
        content_summary = content_summary != "" ? " - $content_summary" : ""

        # Print the file line
        println(io, "$pre$symbol$name$colored_size_str$content_summary")
    else
        println(io, "$pre$symbol$name")
    end
end

format_file_size(size_chars) = return (size_chars < 1000 ? "$(size_chars) chars" : "$(round(size_chars / 1000, digits=2))k chars")

workspace_format_description(ws::Workspace)  = """
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, 
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags. 
Our workspace has a root path: $(ws.root_path)
The projects and their folders:
""" * join([format_project(ws, joinpath(ws.root_path, path), show_files=false) for path in ws.rel_project_paths], "\n")
