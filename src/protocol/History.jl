
@kwdef mutable struct History
	conversations::Dict{String,Conversation}=Dict()
	selected_conv_id::String=""
end


function select_conversation(history::History, conversation_id)
	file_exists, system_message, messages = load_conversation(conversation_id)
	if file_exists
		history.selected_conv_id = conversation_id
		history[conversation_id].system_message = system_message
		history[conversation_id].messages = messages
		println("Conversation id selected: $(history.selected_conv_id)")
	else
		println("Conversation file not found for id: $(conversation_id)")
	end
	return file_exists
end

function generate_new_conversation(history::History, sys_msg)
    prev_id = history.selected_conv_id
    new_id = genid()
    history.conversations[new_id] = Conversation(id=new_id)
    if !isempty(prev_id)
        history.conversations[new_id].common_path      =history.conversations[prev_id].common_path
        history.conversations[new_id].rel_project_paths=history.conversations[prev_id].rel_project_paths
    end
    history.conversations[new_id].system_message = Message(id=genid(), timestamp=now(UTC), role=:system, content=sys_msg)
    history.selected_conv_id = new_id
    curr_conv(history)
end



load(history::History, persistable) = get_all_conversations_without_messages(history)
function get_all_conversations_without_messages(history::History)
	for file in get_all_conversations_file()    
			conv_info = parse_conversation_filename(file)
			history.conversations[conv_info.id] = Conversation(
					timestamp=conv_info.timestamp,
					to_solve=conv_info.to_solve,
					id=conv_info.id
			)
	end
end