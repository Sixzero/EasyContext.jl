
export VirtualWorkspace, init_virtual_workspace_context


@kwdef mutable struct VirtualWorkspace
  rel_path::String
end

init_virtual_workspace_context(conv_ctx) = VirtualWorkspace(mkdir(joinpath(conv_ctx.id, "workspace")))