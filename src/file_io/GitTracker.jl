export GitTracker, init_all, commit_changes

@kwdef mutable struct Branch
	original_branch::String
	repo::GitRepo
	worktreepath::String=""
	branch::String=""                           # max 6 token thing
	# branch_counter::Int=0
	# starting_hash::String
	# commit_msg::Vector{Vector{String}}          # tree like branchnames for multihistory handling
	# hashs::Vector{Dict{String,Vector{String}}}  # tree like hashes  (inside branch "_1"..."_2"...)
end
@kwdef mutable struct GitTracker
	tracked_gits::Vector{Branch}
end
llm_overview(s) = s[1:15]

GitTracker!(ws::Workspace, p::PersistableState, conv, TODO::String) = begin
	gits = Branch[]
	orig_paths = copy(ws.project_paths)
	ws2wt!(ws, p, conv)
	branch = llm_overview(TODO)
	for (i, project_path) in enumerate(ws.project_paths)
		worktreepath=project_path
		push!(gits,Branch(orig, init(orig_paths[i]), worktreepath, branch,0,))
	end
	conv_git = joinpath(p.path, conv.id, "conversation")
push!(git, Branch("", init(conv_git), conv_git))

end

init(path::String) = begin
	local repo
	cd(path) do
		if !isdir(joinpath(".", ".git"))
			println("Initializing new Git repository at $path")
			repo = LibGit2.init(".")
			LibGit2.commit(repo, "Initial commit")
		else
			repo = LibGit2.GitRepo(".")
		end
		git.repo=repo
	end
	return repo
end 

commit_changes(g::GitTracker) = nothing
