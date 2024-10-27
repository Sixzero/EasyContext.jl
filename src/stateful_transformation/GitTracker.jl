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

@kwdef mutable struct Branch
	initial_hash::LibGit2.GitHash
	original_repo::LibGit2.GitRepo
	repo::LibGit2.GitRepo
	worktreepath::String=""
	branch::String=""                           # max 6 token thing
	# branch_counter::Int=0
end
@kwdef mutable struct GitTracker
	tracked_gits::Vector{Branch}
	todo::String=""
end

GitTracker!(ws, p::PersistableState, conv) = begin
	# clean_unnamed()
  branch = "$(INITIAL_BRANCH_NAME)-$(string(floor(Int,datetime2unix(now())))[5:end])"
	
  # TODO if there is branch name collision then regerenrate extending the list what we 'don't want' 
	gits = Branch[]
	for (i, project_path) in enumerate(ws.project_paths)
		expanded_project_path = expanduser(abspath(expanduser(project_path)))
		# @show expanded_project_path
		!is_git(expanded_project_path) && continue

		# proj_name = basename(normpath(project_path))
		proj_name = split(expanded_project_path, "/", keepempty=false)[end]
		worktreepath = joinpath(p.path, conv.id, proj_name) # workpath cannot be ~ ... it MUST be expanded 
		ws.project_paths[i]=worktreepath

		original_repo = LibGit2.GitRepo(expanded_project_path)
		create_worktree(original_repo, branch, worktreepath)
		orig_branch = LibGit2.head_oid(original_repo)
		# @show orig_branch
		# @show worktreepath
		# @show LibGit2.GitRepo(worktreepath)
		push!(gits, Branch(orig_branch, original_repo, LibGit2.GitRepo(worktreepath), worktreepath, branch))
	end
	ws.root_path, ws.rel_project_paths = resolve(ws.resolution_method, ws.project_paths)
	conv_path = abs_conversaion_path(p, conv)

	init_git(conv_path)
	conv_repo = LibGit2.GitRepo(conv_path)
	push!(gits, Branch(LibGit2.head_oid(conv_repo), conv_repo, conv_repo, conv_path, "master"))
	GitTracker(gits,"")
end

is_git(path)    = isdir(joinpath(path, ".git"))
orig_branch(br) = LibGit2.shortname(br.initial_hash)
commit_changes(g::GitTracker, message::String) = begin
	rename_branch(g, message)
	commit_msg = LLM_commit_changes(message)
	# @show commit_msg
	for git in g.tracked_gits
		# @show git.initial_hash
		repo = git.repo
		LibGit2.add!(repo, ".")        # Stages new and modified files
		
    index = LibGit2.GitIndex(repo)

    tree_id = LibGit2.write_tree!(index)
		parent_ids = LibGit2.GitHash[]
    head_commit = LibGit2.head(repo)    # will this error if no head? maybe I should listen to the Claude Sonnet 3.5? :D
		push!(parent_ids, LibGit2.GitHash(head_commit))
    
		commit_id = LibGit2.commit(repo, commit_msg; committer=TODO4AI_Signature, tree_id=tree_id, parent_ids=parent_ids)
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
rename_branch(g::GitTracker, TODO) = begin
	new_name = ""
	# @show new_name
	# println(join([LibGit2.workdir(git.repo) for git in g.tracked_gits], "\n"))
	for git in g.tracked_gits
		!startswith(git.branch, INITIAL_BRANCH_NAME) && continue
		git.branch in ["master", "main"] && continue
		isempty(new_name) && ((new_name = LLM_branch_name(TODO)); (g.todo=TODO))
	
		# @show LibGit2.workdir(git.original_repo)
		cd(LibGit2.workdir(git.original_repo)) do
			run(`git branch -m "$(git.branch)" "$(new_name)"`)
		end
		git.branch = new_name
	end
end


create_worktree(original_repo, branch_name, worktree_path) = begin
	LibGit2.create_branch(original_repo, branch_name, LibGit2.GitCommit(original_repo, LibGit2.head_oid(original_repo)))
	# @show worktree_path
	# @show branch_name
	# @show "initializing"
	cd(LibGit2.workdir(original_repo)) do
		run(`git worktree add $worktree_path $branch_name`)
	end
	# @show "successfully"
end

merge_git(g::GitTracker) = for branch in g.tracked_gits
	merge_git(branch, g.todo)
end
merge_git(b::Branch, commit_msg::String)                         = merge_git(b.original_repo, b.branch, commit_msg)
merge_git(repo::GitRepo, branch::String, commit_msg::String)     = merge_git(LibGit2.workdir(repo),branch,commit_msg)
merge_git(repo_path::String, branch::String, commit_msg::String) = begin
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


