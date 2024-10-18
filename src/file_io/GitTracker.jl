export GitTracker, init_all, commit_changes
@kwdef mutable struct GitTracker
	original_branch::String
	branch::String                              # max 6 token thing
	branch_counter::Int=0
	commit_msg::Vector{Vector{String}}          # tree like branchnames for multihistory handling
	hashs::Vector{Dict{String,Vector{String}}}  # tree like hashes  (inside branch "_1"..."_2"...)
end



GitTracker(p::PersistableState, conv, ws) = nothing

init_all(g::GitTracker) = nothing
commit_changes(g::GitTracker) = nothing
