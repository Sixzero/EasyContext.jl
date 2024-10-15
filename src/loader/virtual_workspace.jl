
export VirtualWorkspace, init_virtual_workspace_context


@kwdef mutable struct VirtualWorkspace
  rel_path::String
end

init_virtual_workspace_context(conv_ctx) = VirtualWorkspace(joinpath(conv_ctx.id, "workspace"))

(p::PersistableState)(vws::VirtualWorkspace) = ((vws.rel_path = mkdir(abspath(joinpath(p.conversation_path,vws.rel_path)))); vws)
