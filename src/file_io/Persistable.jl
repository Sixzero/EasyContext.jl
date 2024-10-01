
@kwdef mutable struct PersistableState
	conversation_path::String=""
end

Persistable(path) = (mkpath(path); PersistableState(path))

CONVERSATION_DIR(p::PersistableState) = p.conversation_path

# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)

to_disk_custom!(conv::ConversationCTX, ::PersistableState) = nothing