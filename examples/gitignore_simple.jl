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
    patterns = get_accumulated_ignore_patterns(file_path, folder_path, [".gitignore"], cache)
    return is_ignored_by_patterns(file_path, patterns)
end

# r = check_folder_gitignore(["../todoforai/frontend"])
# r = check_folder_gitignore([".", "../todoforai/frontend"])
# r = check_folder_gitignore(["."])
# @show (r)
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/target/release/bundle/appimage/build_appimage.sh") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/build_appimage.sh") == false
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/.next") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/.next") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/.next/also") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/.pnp.js") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/.pnp.jss") == false
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/target/CACHEDIR.TAG") == true
is_file_ignored("../todoforai/frontend", "../todoforai/frontend/src-tauri/tauri.conf.json") == false

#%%

workspace = init_workspace_context(["../todoforai/frontend"])
process_workspace_context(workspace, "What is tauri.config.json file?")

