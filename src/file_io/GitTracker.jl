export GitTracker, init_all, commit_changes

using LibGit2

const TODO4AI_Signature::LibGit2.Signature = LibGit2.Signature("todo4.ai", "tracker@todo4.ai")


@kwdef mutable struct Branch
	initial_hash::GitHash
	repo::GitRepo
	worktreepath::String=""
	branch::String=""                           # max 6 token thing
	# branch_counter::Int=0
end
@kwdef mutable struct GitTracker
	tracked_gits::Vector{Branch}
end

GitTracker!(ws::Workspace, p::PersistableState, conv, TODO::String) = begin
  branch = LLM_overview(TODO, max_token=8, extra="It will be used as branch name so use hyphens (-) to separate words between the branch name.")
  # TODO if there is branch name collision then regerenrate extending the list what we 'don't want' 
	gits = Branch[]
	orig_paths = copy(ws.project_paths)
	branch = llm_overview(TODO)
	for (i, project_path) in enumerate(ws.project_paths)
		!is_git(project_path) && continue
		repo = LibGit2.GitRepo(project_path)
		# proj_name = basename(normpath(project_path))
		proj_name = basename(abspath(project_path))
		worktreepath = joinpath(p.path, conv.id, proj_name)
		ws.project_paths[i]=worktreepath
		orig_branch = LibGit2.head_oid(LibGit2.GitRepo(worktreepath))
		push!(gits,Branch(orig_branch, repo, worktreepath, branch,0,branch))
	end
	conv_path = conversaion_path(p, conv)
	push!(gits, Branch("", init_git(conv_path), conv_path, branch))

end

is_git(path)    = isdir(joinpath(path, ".git"))
orig_branch(br) = LibGit2.shortname(br.initial_hash)
commit_changes(g::GitTracker, message::String) = begin
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
    
		commit_id = LibGit2.commit(repo, message; committer=TODO4AI_Signature, tree_id=tree_id, parent_ids=parent_ids)
	end
end
init_git(path::String, forcegit = true) = begin
	if forcegit
		println("Initializing new Git repository at $path")
		repo = LibGit2.init(path)
		LibGit2.commit(repo, "Initial commit")
	else 
		@assert false "yeah this end is unsupported now :D.. TODO"
		return nothing
	end
end 
