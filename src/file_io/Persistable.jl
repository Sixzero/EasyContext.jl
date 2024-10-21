
using JLD2

@kwdef mutable struct PersistableState
	path::String
	format::String="jld2"
end

PersistableState(path::String) = (mkpath(path); PersistableState(path=home_abrev(path)))


# persist!(conv::ConversationCTX) = save_message(conv)
# save_message(conv::ConversationCTX) = save_conversation_to_file(conv)
