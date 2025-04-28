using EasyContext
using EasyContext: get_accumulated_ignore_patterns, is_ignored_by_patterns, GitIgnoreCache, Workspace
using EasyContext: get_filtered_files_and_folders, get_project_files

# Function to check files in a folder against gitignore rules
function check_folder_gitignore(folder_paths)
    workspace = Workspace(folder_paths, verbose=false)
    included_files = get_project_files(workspace)
end

# Function to check if a specific file is ignored
function is_file_ignored(folder_path, file_path)
    cache = GitIgnoreCache()
    patterns = get_accumulated_ignore_patterns(folder_path, folder_path, [".gitignore"], cache)
    return is_ignored_by_patterns(file_path, patterns, folder_path)
end

r = check_folder_gitignore(["../todoforai/frontend"])
# r = check_folder_gitignore([".", "../todoforai/frontend"])
# r = check_folder_gitignore(["."])
@show length(r)
;
