include("token_counter.jl")

export WorkspaceLoader


const path_separator="/"

@kwdef mutable struct Workspace
	project_paths::Vector{String}
	rel_project_paths::Vector{String}=String[]
	common_path::String=""
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
		"spec", "specs", "examples", "docs", "dist", "python", "benchmarks", "node_modules", 
		"conversations", "archived", "archive", "test_cases", ".git" ,"playground"
	]
	IGNORED_FILE_PATTERNS::Vector{String} = [
		".log", "config.ini", "secrets.yaml", "Manifest.toml", ".gitignore", ".aiignore", ".aishignore", "Project.toml" # , "README.md"
	]
	IGNORE_FILES::Vector{String} = [
		".gitignore", ".aishignore"
	]


end

WorkspaceLoader(project_paths::Vector{String}=String[]) = begin
		common_path, rel_project_paths = find_common_path_and_relatives(project_paths)
		common_path !== "" && (cd(common_path); println("Project path initialized: $(common_path)"))
    Workspace(;project_paths, rel_project_paths, common_path)
end

(ws::Workspace)()::Vector{String} = return vcat(get_project_files(ws)...)
function (ws::Workspace)(chunker)
	chunks, sources = RAGTools.get_chunks(chunker, ws())
	return OrderedDict(sources .=> chunks)
end



function get_project_files(w::Workspace)
	all_files = String[]
	for path in w.rel_project_paths
			append!(all_files, get_project_files(w, path))
	end
	return all_files
end
function get_project_files(w::Workspace, path::String)
	files = String[]
	ignore_cache = Dict{String, Vector{String}}()
	ignore_stack = Pair{String, Vector{String}}[]
	
	for (root, dirs, files_in_dir) in walkdir(path, topdown=true)
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

set_project_path(path::String) = path !== "" && (cd(path); println("Project path initialized: $(path)"))
set_project_path(w::Workspace) = set_project_path(w.common_path)
set_project_path(w::Workspace, paths) = begin
    w.common_path, w.rel_project_paths = find_common_path_and_relatives(paths)
    set_project_path(w)
end


function find_common_path_and_relatives(paths)
	isempty(paths)   && return "",          String[]
	length(paths)==1 && return abspath(paths[1]), ["."]
	
	abs_paths = abspath.(paths)
	common_prefix = commonprefix(abs_paths)
	common_prefix = endswith(common_prefix, path_separator) ? common_prefix : common_prefix * path_separator
	
	relative_paths = relpath.(abs_paths, common_prefix)
	
	return common_prefix, relative_paths
end

function commonprefix(paths)
	splitted_paths = splitpath.(paths)
	for i in 1:100
			!allequal(p[i] for p in splitted_paths) && return joinpath(splitted_paths[1][1:i-1])
	end
	return paths[1]
end


print_project_tree(w::Workspace;             show_tokens::Bool=false) = print_project_tree(w, w.rel_project_paths; show_tokens)
print_project_tree(w, paths::Vector{String}; show_tokens::Bool=false) = [print_project_tree(w, path; show_tokens) for path in paths]
print_project_tree(w, path::String;          show_tokens::Bool=false) = begin
    files = get_project_files(w, path)
    rel_paths = sort([relpath(f, path) for f in files])
    
    println("Project structure:")
    prev_parts = String[]
    for (i, file) in enumerate(rel_paths)
        parts = splitpath(file)
        
        # Find the common prefix with the previous file
        common_prefix_length = findfirst(j -> j > length(prev_parts) || parts[j] != prev_parts[j], 1:length(parts)) - 1
        
        # Print directories that are new in this path
        for j in (common_prefix_length + 1):(length(parts) - 1)
            print_tree_line(parts[1:j], j, i == length(rel_paths), false, rel_paths[i+1:end])
        end
        
        # Print the file (or last directory) with token count
        print_tree_line(parts, length(parts), i == length(rel_paths), true, rel_paths[i+1:end], joinpath(path, file), show_tokens=show_tokens)
        
        prev_parts = parts
    end
end

function print_tree_line(parts, depth, is_last_file, is_last_part, remaining_paths, full_path=""; show_tokens::Bool=false)
	prefix = ""
	for k in 1:(depth - 1)
			prefix *= any(p -> startswith(p, join(parts[1:k], "/")), remaining_paths) ? "│   " : "    "
	end
	
	symbol = is_last_file && is_last_part ? "└── " : "├── "
	name = parts[end]

	
	if !isempty(full_path) && isfile(full_path)
		full_file = read(full_path, String)
		name *= show_tokens ? " ($(count_tokens(full_file)))" : ""
		size_chars = count(c -> !isspace(c), full_file)
		if size_chars > 10000
			size_str = format_file_size(size_chars)
			color, reset = size_chars > 20000 ? ("\e[31m", "\e[0m") : ("", "") # Red color for files over 20k chars
			println("$prefix$symbol$name $color($size_str)$reset")
		else
			println("$prefix$symbol$name")
		end
	else
		println("$prefix$symbol$name$(is_last_part ? "" : "/")")
	end
end

format_file_size(size_chars) = return (size_chars < 1000 ? "$(size_chars) chars" : "$(round(size_chars / 1000, digits=2))k chars")
