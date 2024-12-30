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
        "proto", "proto3", "graphql", "prisma", "yml", "yaml"
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
Base.cd(f::Function, workspace::Workspace) = !isempty(workspace.root_path) ? cd(f, workspace.root_path) : f()

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
function (ws::Workspace)(chunker)
    chunks, sources = RAGTools.get_chunks(chunker, get_project_files(ws))
    return OrderedDict(zip(sources, chunks))
end

function get_project_files(w::Workspace)
    all_files = String[]
    cd(w) do
        for path in w.rel_project_paths
            append!(all_files, get_filtered_files_and_folders(w, path)[1])
        end
    end
    return all_files
end

function get_filtered_files_and_folders(w::Workspace, path::String)
    project_files = String[]
    filtered_files = String[]
    filtered_dirs  = String[]

    # Parse gitignore at root path first
    ignore_patterns = parse_ignore_files(path, w.IGNORE_FILES)

    for (root, dirs, files_in_dir) in walkdir(path, topdown=true, follow_symlinks=true)
        # Add patterns from any .gitignore found in subdirectories
        local_ignore_patterns = vcat(ignore_patterns, parse_ignore_files(root, w.IGNORE_FILES))

        # Handle filtered folders
        if any(d -> d in w.FILTERED_FOLDERS, splitpath(relpath(root)))
            push!(filtered_dirs, root)
            empty!(dirs)
            continue
        end

        # Process directories
        for d in dirs
            dir_path = joinpath(root, d)
            if is_ignored_by_patterns(dir_path, local_ignore_patterns, path)
                push!(filtered_dirs, dir_path)
                filter!(x -> x != d, dirs)
            end
        end

        # Process files
        for file in files_in_dir
            file_path = joinpath(root, file)
            # First check if it's ignored, then check if it's a project file
            if is_ignored_by_patterns(file_path, local_ignore_patterns, path) ||
               ignore_file(file_path, w.IGNORED_FILE_PATTERNS) ||
               !is_project_file(lowercase(file), w.PROJECT_FILES, w.FILE_EXTENSIONS)
                push!(filtered_files, file_path)
            else
                push!(project_files, file_path)
            end
        end
    end

    return project_files, filtered_files, filtered_dirs
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
                    summary_callback::Function=default_summary_callback, 
                    do_print::Bool=true) = print_project_tree(w, w.rel_project_paths; show_tokens, show_files, filewarning, summary_callback, do_print)
print_project_tree(w, paths::Vector{String}; 
                    show_tokens::Bool=false, 
                    show_files::Bool=true, 
                    filewarning::Bool=true, 
                    summary_callback::Function=default_summary_callback, 
                    do_print::Bool=true) = 
    [print_project_tree(w, path; show_tokens, show_files, filewarning, summary_callback, do_print) for path in paths]
function print_project_tree(
    w::Workspace, 
    path::String; 
    show_tokens::Bool = false, 
    show_files::Bool = true, 
    filewarning::Bool = true,
    summary_callback::Function = default_summary_callback,
    do_print::Bool = true
)
    cd(w) do
        project_files, filtered_files, filtered_folders = get_filtered_files_and_folders(w, path)
        
        # Create async tasks for summaries
        summary_tasks = Dict{String, Task}()
        
        # Generate header
        header = "Project [$(normpath(path))/]$(get_project_name(abspath(path)))"
        tree_str = generate_tree_string(
            path; 
            show_tokens = show_tokens, 
            only_dirs = !show_files, 
            filtered_folders = filtered_folders, 
            filtered_files = filtered_files,
            filewarning = filewarning,
            summary_callback = summary_callback,
            summary_tasks = summary_tasks  # Pass the tasks dictionary
        )
        isempty(tree_str) && (tree_str = "└── (no subfolder)")
        
        # Wait for all summaries to complete
        summaries = Dict{String, String}()
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
end

function generate_tree_string(
    path::String;
    show_tokens::Bool = false,
    only_dirs::Bool = false,
    filtered_folders::Vector{String} = String[],
    filtered_files::Vector{String} = String[],
    filewarning::Bool = true,
    summary_callback::Function = default_summary_callback,
    summary_tasks::Dict{String, Task} = Dict{String, Task}()
)
    io = IOBuffer()
    _print_tree(
        io,
        path;
        pre = "",
        show_tokens = show_tokens,
        only_dirs = only_dirs,
        filtered_folders = filtered_folders,
        filtered_files = filtered_files,
        filewarning = filewarning,
        summary_callback = summary_callback,
        summary_tasks = summary_tasks
    )
    return String(take!(io))
end

function _print_tree(
    io::IO, 
    path::String; 
    pre::String = "", 
    show_tokens::Bool = false, 
    only_dirs::Bool = false,
    filtered_folders::Vector{String} = String[],
    filtered_files::Vector{String} = String[],
    filewarning::Bool = true,
    summary_callback::Function = default_summary_callback,
    summary_tasks::Dict{String, Task} = Dict{String, Task}()
)
    # Read entries in the current directory
    entries = readdir(path)
    dirs = sort([e for e in entries if isdir(joinpath(path, e))])
    files = sort([e for e in entries if isfile(joinpath(path, e))])


    # Count total entries to determine when to use "└──"
    total_entries = length(dirs) + (only_dirs ? 0 : length(files))
    total_entries == 0 && return

    # Print files if only_dirs is false
    idx = 0
    if !only_dirs
        for file in files
            idx += 1
            filepath = joinpath(path, file)
            filepath in filtered_files && continue
            is_last = isempty(dirs) && idx == length(files)
            print_file(io, filepath, is_last, pre; 
                show_tokens, 
                filewarning, 
                summary_callback,
                summary_tasks
            )
        end
    end

    # Print directories
    idx = 0
    for dir in dirs
        idx += 1
        joinpath(path, dir) in filtered_folders && continue
        is_last = idx == length(dirs)
        next_pre = pre * (is_last ? "    " : "│   ")
        println(io, pre * (is_last ? "└── " : "├── ") * dir * "/")
        # Recursively print subdirectories
        _print_tree(io, joinpath(path, dir); pre=next_pre, show_tokens, only_dirs, filtered_folders, filtered_files, filewarning, summary_callback, summary_tasks)
    end
end

function print_file(
    io::IO,
    full_path::String,
    is_last::Bool,
    pre::String = "";
    show_tokens::Bool = false,
    filewarning::Bool = true,
    summary_callback::Function = nothing,
    summary_tasks::Dict{String, Task} = Dict{String, Task}()
)
    symbol = is_last ? "└── " : "├── "
    name = basename(full_path)

    if isfile(full_path)
        size_chars = 0
        content_summary = "{{SUMMARY:$full_path}}"  # placeholder

        try
            full_file = read(full_path, String)
            size_chars = count(c -> !isspace(c), full_file)
            name *= show_tokens ? " ($(count_tokens(full_file)))" : ""

            # Create async task for summary
            if summary_callback !== nothing
                summary_tasks[full_path] = @async summary_callback(full_path, full_file)
            end
        catch e
            if isa(e, Base.InvalidCharError{Char})
                # If the file contains invalid UTF-8, treat it as binary
                size_chars = filesize(full_path)
                name *= " (binary or invalid UTF-8)"
            else
                rethrow(e)
            end
        end

        # Format the size string
        size_str = ""
        size_chars > 10_000 && (size_str = format_file_size(size_chars))

        # Apply coloring for large files if filewarning is true
        colored_size_str = ""
        if filewarning && size_chars > 20_000
            color, reset = "\e[31m", "\e[0m"
            colored_size_str = " $color($size_str)$reset"
        elseif size_str != ""
            colored_size_str = " ($size_str)"
        end

        println(io, "$pre$symbol$name$colored_size_str$content_summary")
    else
        println(io, "$pre$symbol$name")
    end
end

format_file_size(size_chars) = size_chars < 1000 ? "$(size_chars) chars" : "$(round(size_chars / 1000, digits=2))k chars"

workspace_format_description(ws::Workspace)  = """
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, 
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags. 
Our workspace has a root path: $(ws.root_path)
The projects and their folders:
""" * join(print_project_tree(ws, show_files=true, summary_callback=LLM_summary,  do_print=true), "\n")
