
using JSON3
using JLD2

@kwdef mutable struct PersistableState
	path::String
	PersistableState(path::String) = (mkpath(path); new(expanduser(abspath(expanduser((path))))))
end



# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)
get_conversation_filename(p::PersistableState,conv_id::String) = (files = filter(f -> endswith(f, "_$(conv_id).log"), readdir(p.path)); isempty(files) ? nothing : joinpath(p.path, first(files)))

function generate_overview(conv::CONV, conv_id::String, p::PersistableState)
	@assert false
	sanitized_chars = strip(replace(replace(first(conv.messages[1].content, 32), r"[^\w\s-]" => "_"), r"\s+" => "_"), '_')
	return joinpath(p.path, "$(date_format(conv.timestamp))_$(sanitized_chars)_$(conv_id).log")
end

(p::PersistableState)(conv::Session) = begin
	println(conversaion_path(p, conv))
	mkpath_if_missing(joinpath(p.path, conv.id))
	mkpath_if_missing(conversaion_path(p, conv))
	save_conversation(conversaion_file(p, conv), conv)
	conv
end



export VirtualWorkspace, init_virtual_workspace_path

struct VirtualWorkspace
    rel_path::String
end

function init_virtual_workspace_path(p::PersistableState, conv_ctx::Session)
    vpath = joinpath(conv_ctx.id, "workspace")
    rel_path = mkdir(expanduser(joinpath(p.path, vpath)))
    VirtualWorkspace(rel_path)
end


