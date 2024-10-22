export GitTracker, init_all, commit_changes, GitTracker!

using LibGit2

const TODO4AI_Signature::LibGit2.Signature = LibGit2.Signature("todo4.ai", "tracker@todo4.ai")
const INITIAL_BRANCH_NAME = "unnamed-branch"

LLM_branch_name(TODO)    = LLM_overview(TODO, max_token=8, extra="It will be used as branch name so use hyphens (-) to separate words between the branch name.")
LLM_job_to_do(TODO)      = LLM_overview(TODO, max_token=29, extra="We need this to be a very concise overview about the question")
LLM_commit_changes(TODO) = LLM_overview(TODO, max_token=29, extra="We need a very concise overview about the changes we are planning to make")
# TODoO = "a\ra isay hi"
# new_name = LLM_job_to_do3(TODoO)

@kwdef mutable struct Branch
	initial_hash::LibGit2.GitHash
	repo::LibGit2.GitRepo
	worktreepath::String=""
	branch::String=""                           # max 6 token thing
	# branch_counter::Int=0
end
@kwdef mutable struct GitTracker
	tracked_gits::Vector{Branch}
end

GitTracker!(ws, p::PersistableState, conv, TODO::String) = begin
	# clean_unnamed()
  branch = isempty(TODO) ? "$(INITIAL_BRANCH_NAME)_$(String(Int(datetime2unix(now())))[8:end])" : LLM_branch_name(TODO)
	@show branch
  # TODO if there is branch name collision then regerenrate extending the list what we 'don't want' 
	gits = Branch[]
	for (i, project_path) in enumerate(ws.project_paths)
		!is_git(project_path) && continue
		repo = LibGit2.GitRepo(project_path)
		# proj_name = basename(normpath(project_path))
		proj_name = split(abspath(project_path),"/", keepempty=false)[end]
		worktreepath = joinpath(p.path, conv.id, proj_name)
		ws.project_paths[i]=worktreepath
		create_worktree(repo, branch, worktreepath)
		orig_branch = LibGit2.head_oid(repo)
		@show orig_branch
		@show worktreepath
		push!(gits, Branch(orig_branch, repo, worktreepath, branch))
	end
	ws.root_path, ws.rel_project_paths = resolve(ws.resolution_method, project_paths)
	
	conv_path = conversaion_path(p, conv)
	init_git(conv_path)
	conv_repo = LibGit2.GitRepo(conv_path)
	push!(gits, Branch(LibGit2.head_oid(conv_repo), conv_repo, conv_path, branch))
	GitTracker(gits)
end

is_git(path)    = isdir(joinpath(path, ".git"))
orig_branch(br) = LibGit2.shortname(br.initial_hash)
commit_changes(g::GitTracker, message::String) = begin
	if g.tracked_gits[1].branch[1:length(INITIAL_BRANCH_NAME)] == INITIAL_BRANCH_NAME
		rename(g, message)
	end
	commit_msg = LLM_commit_changes(message)
	for git in g.tracked_gits
		@show git.initial_hash
		@show git.repo
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
rename(g::GitTracker, TODO) = begin
	@show TODO
	new_name = LLM_job_to_do(TODO)
	@show new_name
	for git in g.tracked_gits
		@show LibGit2.path(git.repo)
		@show typeof(LibGit2.path(git.repo))
		cd(String(LibGit2.path(git.repo))) do
			run(`git branch -m $(git.branch) "$(new_name)"`)
		end
		git.branch = new_name
	end
end


create_worktree(repo, branch_name, worktree_path) = begin
	path = LibGit2.path(repo)
	head_oid = LibGit2.head_oid(repo)
	LibGit2.create_branch(repo, branch_name, LibGit2.GitCommit(repo, head_oid))
	@show worktree_path
	@show "initializing"
	cd(String(path)) do
		run(`git worktree add $worktree_path $branch_name`)
	end
	@show "successfully"
end

