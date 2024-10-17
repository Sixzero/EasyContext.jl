
using JLD2

@kwdef mutable struct PersistableState
	conversation_path::String
	format::String="jld2"
end

PersistableState(path::String) = (mkpath(path); PersistableState(conversation_path=home_abrev(path)))

CONVERSATION_DIR(p::PersistableState) = p.conversation_path


# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)
