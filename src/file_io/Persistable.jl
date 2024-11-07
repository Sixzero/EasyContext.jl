
using JSON3
using JLD2

@kwdef mutable struct PersistableState
	path::String
	PersistableState(path::String) = (mkpath(path); new(expanduser(abspath(expanduser((path))))))
end



# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)
