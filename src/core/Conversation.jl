
@kwdef mutable struct ConversationInfo
	id::String=genid()
	timestamp::DateTime=now(UTC)
	sentence::String=""
	system_message::Union{Message,Nothing}=nothing
	messages::Vector{Message}=[]
end


function cut_history!(conv::ConversationInfo; keep=13)
	length(conv.messages) <= keep && return conv.messages
	
	start_index = max(1, length(conv.messages) - keep + 1)
	start_index += (conv.messages[start_index].role == :assistant)
	
	conv.messages = conv.messages[start_index:end]
end

get_message_by_id(conv::ConversationInfo, message_id::String) = findfirst(msg -> msg.id == message_id, conv.messages)

update_message_by_idx(conv::ConversationInfo, idx::Int, new_content::String) = ((conv.messages[idx].content = new_content); conv.messages[idx])
update_message_by_id(conv::ConversationInfo, message_id::String, new_content::String) = begin
	idx = get_message_by_id(conv, message_id)
	isnothing(idx) && @assert false "message with the specified id: $id wasnt found! " 
	update_message_by_idx(conv, idx, new_content)
end

add_user_message!(conv::ConversationInfo, user_question::String) = add_user_message!(conv, create_user_message(user_question))
add_user_message!(conv::ConversationInfo, user_msg::Message)     = push!(conv.messages, user_msg)[end]

add_ai_message!(conv::ConversationInfo, ai_message::String, meta::Dict) = add_ai_message!(conv, create_AI_message(ai_message, meta))
add_ai_message!(conv::ConversationInfo, ai_message::String)             = add_ai_message!(conv, create_AI_message(ai_message))
add_ai_message!(conv::ConversationInfo, ai_msg::Message)                = push!(conv.messages, ai_msg)[end]

add_error_message!(conv::ConversationInfo, error_content::String) = begin
	convmes = conv.messages
	isempty(convmes) && return add_user_message!(conv, error_content)
	return if convmes[end].role == :user 
		add_ai_message!(conv, error_content)
	elseif convmes[end].role == :assistant 
		update_message_by_id(conv, convmes[end].id, convmes[end].content * error_content)
	else
		add_user_message!(conv, error_content)
	end
end


to_dict(conv::ConversationInfo)                = [Dict("role" => "system", "content" => conv().system_message); to_dict_nosys(conv())]
to_dict_nosys(conv::ConversationInfo)          = [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
to_dict_nosys_detailed(conv::ConversationInfo) = [to_dict(message) for message in conv.messages]


function update_last_user_message_meta(conv::ConversationInfo, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Float64)
	msg = conv.messages[end]
	msg.itok       = itok
	msg.otok       = otok
	msg.cached     = cached
	msg.cache_read = cache_read
	msg.price      = price
	msg.elapsed    = elapsed
	msg
end
