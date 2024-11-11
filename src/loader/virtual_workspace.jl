
export VirtualWorkspace, init_virtual_workspace_path

struct VirtualWorkspace
    rel_path::String
end

function init_virtual_workspace_path(p::PersistableState, conv_ctx::Session)
    vpath = joinpath(conv_ctx.id, "workspace")
    rel_path = mkdir(expanduser(joinpath(p.path, vpath)))
    VirtualWorkspace(rel_path)
end


