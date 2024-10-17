
@kwdef mutable struct History
	to_solve::Dict{String,ConversationX}=Dict()
	selected_conv_id::String=""
end

get_all_conversations_file(p) = readdir(CONVERSATION_DIR(p))

function select_conversation(history::History, conv_id)
	file_exists, conv = load_conv(conv_id)
	if file_exists
		history.selected_conv_id = conv_id
		history.to_solve[conv_id] = conv
		println("Conversation id selected: $(history.selected_conv_id)")
	else
		println("Conversation file not found for id: $(conv_id)")
	end
	return file_exists
end

function generate_new_to_solve(history::History, sys_msg)
	prev_id = history.selected_conv_id
	new_conv = Conversation_from_sysmsg(;sys_msg)
	to_solve = ConversationX(new_conv)
	history.to_solve[to_solve.id] = to_solve 
	history.selected_conv_id = to_solve.id
end

load(history::History, persistable::PersistableState) = get_all_conversations_without_messages(history, persistable)
function get_all_conversations_without_messages(history::History, persistable)
	for file in get_all_conversations_file(persistable)    
			conv_info = parse_conversation_filename(file)
			history.to_solve[conv_info.id] = ConversationX(
				id=conv_info.id,
				timestamp=conv_info.timestamp,
				to_solve=conv_info.to_solve,
			)
	end
end