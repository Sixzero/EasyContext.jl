
export init_virtual_workspace_path


init_virtual_workspace_path(conv_ctx) = joinpath(conv_ctx.id, "workspace")
(p::PersistableState)(path::String) = (mkdir(joinpath(p.conversation_path, path)))