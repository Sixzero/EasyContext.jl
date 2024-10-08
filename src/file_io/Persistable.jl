
using JLD2

@kwdef mutable struct PersistableState
	conversation_path::String="conversations"
	format::String="jld2"
end

Persistable(path::String) = (mkpath(path); PersistableState(conversation_path=path))

CONVERSATION_DIR(p::PersistableState) = p.conversation_path

# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)
