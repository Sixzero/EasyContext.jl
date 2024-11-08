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
        "rst", "adoc", "tex", "sty", "gradle", "sbt", "xml"
    ]
    FILTERED_FOLDERS::Vector{String} = [
        "build",
        "spec", "specs", "examples", "docs", "dist", "python", "benchmarks", "node_modules", 
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

# cd_rootpath(ws::Workspace) = begin
#     curr_rel_path  = [normpath(joinpath(pwd(),rel_path)) for rel_path in ws.rel_project_paths]
#     ideal_rel_path = [normpath(joinpath(root_path,rel_path)) for rel_path in ws.rel_project_paths]
#     new_rel_path = relpath.(ideal_rel_path, curr_rel_path)
#     cd(root_path)
#     println("Project path initialized: $(path)")

#     ws.rel_project_paths = new_rel_path
# end
function Workspace(project_paths::Vector{String}; 
                    resolution_method::AbstractResolutionMethod=FirstAsRootResolution(), 
                    virtual_ws=nothing,
                    show_tokens=false,
                    verbose=true)

    !isnothing(virtual_ws) && push!(project_paths, virtual_ws.rel_path)
    # Check if all paths exist
    for path in project_paths
        @assert isdir(expanduser(path)) "Path does not exist or is not a directory: $path"
    end
    
    root_path, rel_project_paths = resolve(resolution_method, project_paths)
    original_dir = pwd()
    workspace = Workspace(;project_paths, rel_project_paths, root_path, resolution_method, original_dir, show_tokens)
    # root_path !== "" && cd_rootpath(workspace)
    
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
    cd(w.root_path) do
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

print_project_tree(w::Workspace) = print_project_tree(w, w.rel_project_paths; show_tokens)
print_project_tree(w, paths::Vector{String}; show_tokens::Bool=false) = [print_project_tree(w, path; show_tokens) for path in paths]
print_project_tree(w, path::String;          show_tokens::Bool=false) = begin
    println("Project structure:")
    files = get_project_files(w, path)
    rel_paths = sort([relpath(f, path) for f in files])
    print_tree(rel_paths, path; show_tokens)
end

function print_tree(paths::Vector{String}, root_path::String=""; show_tokens::Bool=false, pre="")
    if isempty(paths)
        return
    end

    # Group files by their immediate parent directory
    groups = Dict{String,Vector{String}}()
    for path in paths
        parts = splitpath(path)
        if length(parts) == 1
            # Files in root
            push!(get!(groups, "", String[]), path)
        else
            # Files in subdirectories
            push!(get!(groups, parts[1], String[]), joinpath(parts[2:end]...))
        end
    end

    # Sort directories and files
    sorted_keys = sort(collect(keys(groups)))
    
    # Process each group
    for (i, dir) in enumerate(sorted_keys)
        is_last_dir = i == length(sorted_keys)
        
        if dir == ""
            # Print files in current directory
            files = sort(groups[dir])
            for (j, file) in enumerate(files)
                is_last_file = j == length(files) && is_last_dir  # Only use corner mark if it's the last file AND last directory
                print_file(joinpath(root_path, file), is_last_file, pre; show_tokens)
            end
        else
            # Print directory and its contents
            println(pre * (is_last_dir ? "└── " : "├── ") * dir * "/")
            new_pre = pre * (is_last_dir ? "    " : "│   ")
            print_tree(groups[dir], joinpath(root_path, dir); show_tokens, pre=new_pre)
        end
    end
end

function print_file(full_path::String, is_last::Bool, pre::String=""; show_tokens::Bool=false)
    symbol = is_last ? "└── " : "├── "
    name = basename(full_path)
    
    if isfile(full_path)
        full_file = read(full_path, String)
        name *= show_tokens ? " ($(count_tokens(full_file)))" : ""
        size_chars = count(c -> !isspace(c), full_file)
        if size_chars > 10000
            size_str = format_file_size(size_chars)
            color, reset = size_chars > 20000 ? ("\e[31m", "\e[0m") : ("", "") # Red color for files over 20k chars
            println("$pre$symbol$name $color($size_str)$reset")
        else
            println("$pre$symbol$name")
        end
    else
        println("$pre$symbol$name")
    end
end

tree_string(path, w::Workspace)                             = String(take!(tree_string(path, w.FILTERED_FOLDERS)))
tree_string(path, FILTERED_FOLDERS, pre="", buf=IOBuffer()) = begin
    dirs = filter(d -> isdir(joinpath(path,d)) && !(d in FILTERED_FOLDERS), readdir(path))
    for (i, d) in enumerate(dirs)
        last = i == length(dirs)
        println(buf, pre * (last ? "└── " : "├── ") * d)
        new_p = joinpath(path, d)
        tree_string(new_p, FILTERED_FOLDERS, pre * (last ? "    " : "│   "), buf)
    end
    buf
end

format_file_size(size_chars) = return (size_chars < 1000 ? "$(size_chars) chars" : "$(round(size_chars / 1000, digits=2))k chars")

format_project(ws, path) = begin
    folder_tree = tree_string(path, ws)
    folder_tree == "" && (folder_tree="└── (no subfolder)")
    """Project $(get_project_name(path)) [$(normpath(path))]
    $(folder_tree)
    """
end
workspace_format_description(ws::Workspace)  = """
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, 
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags. 
Our workspace has a root path: $(ws.root_path)
The projects and their folders: 
""" * join([format_project(ws, joinpath(ws.root_path, path)) for path in ws.rel_project_paths], "\n")

get_project_name(p) = basename(endswith(p, "/.") ? p[1:end-2] : rstrip(p, '/'))
