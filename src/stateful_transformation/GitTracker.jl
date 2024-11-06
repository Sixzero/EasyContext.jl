export GitTracker, init_all, commit_changes, GitTracker!

using LibGit2

const TODO4AI_Signature::LibGit2.Signature = LibGit2.Signature("todo4.ai", "tracker@todo4.ai")
const INITIAL_BRANCH_NAME = "unnamed-branch"

LLM_branch_name(TODO)    = LLM_overview(TODO, max_token=7, extra="It will be used as branch name so use hyphens (-) to separate words between the branch name.\n \
Avoid characters like: quote (\"), space ( ), tilde (~), caret (^), colon (:), questionmark (?), asterisk (*), or open bracket ([)")
LLM_job_to_do(TODO)      = LLM_overview(TODO, max_token=29, extra="We need this to be a very concise overview about the question")
LLM_commit_changes(TODO) = LLM_overview(TODO, max_token=29, extra="We need a very concise overview about the changes we are planning to make")
# TODoO = "a\ra isay hi"
# new_name = LLM_job_to_do3(TODoO)

# initial_hash::LibGit2.GitHash
@kwdef mutable struct WorkTree
	repo::LibGit2.GitRepo
end
@kwdef mutable struct GitTracker
	tracked_gits::Vector{WorkTree}
	todo::String=""
end

GitTracker!(ws, p::PersistableState, conv) = begin
	# clean_unnamed()
  # TODO if there is branch name collision then regerenrate extending the list what we 'don't want' 
	gits = WorkTree[]
	for (i, project_path) in enumerate(ws.project_paths)
		expanded_project_path = expanduser(abspath(expanduser(project_path)))
		# @show expanded_project_path
		!is_git(expanded_project_path) && continue

		# proj_name = basename(normpath(project_path))
		proj_name           = get_project_name(expanded_project_path)
		worktreepath        = joinpath(p.path, conv.id, proj_name) # workpath cannot be ~ ... it MUST be expanded 
		ws.project_paths[i] = worktreepath

		create_worktree(expanded_project_path, worktreepath)
		# @show worktreepath
		push!(gits, WorkTree(LibGit2.GitRepo(worktreepath)))
	end
	ws.root_path, ws.rel_project_paths = resolve(ws.resolution_method, ws.project_paths)
	conv_path = abs_conversaion_path(p, conv)

	init_git(conv_path)
	conv_repo = LibGit2.GitRepo(conv_path)
	push!(gits, WorkTree(conv_repo))
	GitTracker(gits, "")
end
GitTracker(base_worktree_path::String) = begin
	gits = WorkTree[]
	for folder in readdir(base_worktree_path)
		repo_path = joinpath(base_worktree_path, folder)
		push!(gits, WorkTree(LibGit2.GitRepo(repo_path)))
	end
	GitTracker(gits, "")
end

is_git(path)    = isdir(joinpath(path, ".git"))
commit_changes(g::GitTracker, message::String) = begin
	isempty(g.todo) && (g.todo = message)  # Initialize the MAIN todo!
	commit_msg = LLM_commit_changes(message)
	# @show commit_msg
	for git in g.tracked_gits
		repo = git.repo
		cd(LibGit2.workdir(repo)) do
			LibGit2.add!(repo, ".")        # Stages new and modified files
			
			index = LibGit2.GitIndex(repo)

			tree_id = LibGit2.write_tree!(index)
			parent_ids = LibGit2.GitHash[]
			head_commit = LibGit2.head(repo)    # will this error if no head? maybe I should listen to the Claude Sonnet 3.5? :D
			push!(parent_ids, LibGit2.GitHash(head_commit))
			
			commit_id = LibGit2.commit(repo, commit_msg; committer=TODO4AI_Signature, tree_id=tree_id, parent_ids=parent_ids)
		end
	end
end
init_git(path::String, forcegit = true) = begin
	if forcegit
		println("Initializing new Git repository at $path")
		repo = LibGit2.init(path)
		idx = LibGit2.GitIndex(repo)
		tree_id = LibGit2.write_tree!(idx)
  
		LibGit2.commit(repo, "Initial commit"; author=TODO4AI_Signature, committer=TODO4AI_Signature, tree_id=tree_id)
	else 
		@assert false "yeah this end is unsupported now :D.. TODO"
		return nothing
	end
	
end 

create_worktree(expanded_project_path, worktree_path) = begin
	cd(expanded_project_path) do
		run(pipeline(`git worktree add -d $worktree_path`, stdout=devnull, stderr=devnull))
	end
end
merge_git(g::GitTracker) = begin
	branch = LLM_branch_name(g.todo)
	commit_msg = LLM_commit_changes(g.todo)
	for worktree in g.tracked_gits
		merge_git(worktree, branch, commit_msg)
	end
end
merge_git(w::WorkTree, branch::String, commit_msg::String) = merge_git(w.repo, branch, commit_msg)
merge_git(worktree_repo::GitRepo, branch::String, commit_msg::String) = merge_git(LibGit2.workdir(worktree_repo), branch, commit_msg)
merge_git(worktree_path::String, branch::String, commit_msg::String; skip_merge=String[]) = begin
	# we should check if the worktree was already merged... So we don't merge it twice
	basename(worktree_path) in skip_merge && return
	repo_path = ""
	cd(worktree_path) do
		run(`git checkout -b $(branch)`) # no name collision please while loop should be here...
		basename(worktree_path) in ["conversation"] && return
		git_dir = read(`git rev-parse --git-dir`, String)
		repo_path = dirname(replace(strip(git_dir), r".git/worktrees/[^/]*" => ""))
	end
	isempty(repo_path) && return # Return early if not a worktree
	cd(repo_path) do

		stash_result = read(`git stash save "Temp stash before $(branch)"`, String)
		has_stash = !occursin("No local changes to save", stash_result)
		merge_result = read(`git merge $(branch) --no-ff -m "$(commit_msg)"`, String)
		(occursin("CONFLICT", merge_result) || occursin("error:", merge_result)) && (@warn ("Merge conflict detected: $merge_result"); return)
		!has_stash && return
		pop_result = read(`git stash pop`, String)
		(occursin("CONFLICT", pop_result) || occursin("error:", pop_result)) && @warn ("Stash pop conflict detected: $pop_result")
	end
end

