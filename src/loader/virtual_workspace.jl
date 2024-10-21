
export VirtualWorkspace, init_virtual_workspace_path

struct VirtualWorkspace
    rel_path::String
end

function init_virtual_workspace_path(conv_ctx::ConversationX)
    rel_path = joinpath(conv_ctx.id, "workspace")
    VirtualWorkspace(rel_path)
end

function (p::PersistableState)(vws::VirtualWorkspace)
	vws.rel_path = mkdir(joinpath(p.path, vws.rel_path))
	vws
end

