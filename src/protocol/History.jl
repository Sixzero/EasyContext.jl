
@kwdef mutable struct History
	TODOs::Dict{String,String} = Dict() # id => todo description
end



JSON3.StructTypes.StructType(::Type{History}) = JSON3.StructTypes.Struct()
add_conversation!(history::History, conv::ConversationX;) = history.TODOs[conv.id] = TODO(conv)

save_history(history::History, p::PersistableState) = write(joinpath(p.path, "history.json"), JSON3.pretty(history))
load_history(p::PersistableState) = begin
	history_path = joinpath(p.path, "history.json")
	isfile(history_path) ? JSON3.read(read(history_path, String), History) : History()
end

get_all_conversations_file(p) = readdir(p.path)




@kwdef mutable struct SelectedTODO
	name::String=""
end


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