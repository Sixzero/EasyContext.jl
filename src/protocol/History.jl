
@kwdef mutable struct History
	to_solve::Dict{String,ToSolve}=Dict()
	selected_conv_id::String=""
end

get_all_conversations_file(p) = readdir(CONVERSATION_DIR(p))

function select_conversation(history::History, tosolve_id)
	file_exists, tosolve = load_tosolve(tosolve_id)
	if file_exists
		history.selected_conv_id = tosolve_id
		history.to_solve[tosolve_id] = tosolve
		println("Conversation id selected: $(history.selected_conv_id)")
	else
		println("Conversation file not found for id: $(tosolve_id)")
	end
	return file_exists
end

function generate_new_to_solve(history::History, sys_msg)
	prev_id = history.selected_conv_id
	new_conv = Conversation_from_sysmsg(;sys_msg)
	to_solve = ToSolve(new_conv)
	history.to_solve[to_solve.id] = to_solve 
	history.selected_conv_id = to_solve.id
end

load(history::History, persistable) = get_all_conversations_without_messages(history, persistable)
function get_all_conversations_without_messages(history::History, persistable)
	for file in get_all_conversations_file(persistable)    
			conv_info = parse_conversation_filename(file)
			history.to_solve[conv_info.id] = ToSolve(
				id=conv_info.id,
				timestamp=conv_info.timestamp,
				to_solve=conv_info.to_solve,
			)
	end
end