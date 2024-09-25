
@kwdef mutable struct History
	conversations::Dict{String,ConversationProcessor}=Dict()
	selected_conv_id::String=""
end


function get_all_conversations_without_messages(history::History)
	for file in get_all_conversations_file()    
			conv_info = parse_conversation_filename(file)
			history.conversations[conv_info.id] = ConversationProcessor(
					timestamp=conv_info.timestamp,
					sentence=conv_info.sentence,
					id=conv_info.id
			)
	end
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

function generate_new_conversation(history::History)
    prev_id = history.selected_conv_id
    new_id = genid()
    history.conversations[new_id] = ConversationProcessor(id=new_id)
    if !isempty(prev_id)
        history.conversations[new_id].common_path      =history.conversations[prev_id].common_path
        history.conversations[new_id].rel_project_paths=history.conversations[prev_id].rel_project_paths
    end
    history.conversations[new_id].system_message = Message(id=genid(), timestamp=now(UTC), role=:system, content=SYSTEM_PROMPT(ctx=projects_ctx(history.conversations[new_id].rel_project_paths)))
    history.selected_conv_id = new_id
    curr_conv(history)
end


project_ctx(path) = """
The codebase you are working on:
================================
$(get_all_project_files(path))
================================
This is the latest version of the codebase, chats after these can only hold same or older versions only. If something is not like you proposed that is probably that change was not accepted, or there were manual edits in the code, which we should keep probably.
"""
projects_ctx(paths::Vector{String}) = """
The codebase you are working on:
================================
$(join(get_all_project_files.(paths),"\n================================\n"))
================================
This is the latest version of the codebase, chats after these can only hold same or older versions only. If something is not like you proposed that is probably that change was not accepted, or there were manual edits in the code, which we should keep probably.
"""

get_codebase_ctx(question, path, ) = """
The codebase you are working on:
================================
$(project_ctx(path, question))
================================
This is the latest version of the codebase, chats after these can only hold same or older versions only. If something is not like you proposed that is probably that change was not accepted, or there were manual edits in the code, which we should keep probably.
"""
