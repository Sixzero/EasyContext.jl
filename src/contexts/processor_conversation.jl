

@kwdef mutable struct ConversationProcessor
	conv::ConversationInfo
	max_history::Int = 10
end

Anthropic.ai_stream_safe(conv::ConversationProcessor; model, system_msg=conv().system_message, max_tokens::Int=MAX_TOKEN, printout=true, cache=nothing) = ai_stream_safe(conv(); system_msg, model, max_tokens, printout, cache)

ConversationProcessorr(;sys_msggg::String) = ConversationProcessor(
	conv=ConversationInfo(system_message=Message(id=genid(), timestamp=now(UTC), role=:system, content=sys_msggg)),
	max_history=10)
(conv::ConversationProcessor)() = conv.conv


save!(conv::ConversationProcessor, msg::Message) =  begin
	push!(conv().messages, msg)
	if length(conv().messages) > conv.max_history
			cut_history!(conv(), keep=conv.max_history)
	end
	return msg
end

save_error!(conv::ConversationProcessor, msg_content::String) =  begin
	
end


get_cache_setting(conv::ConversationProcessor) = begin
	if length(conv().messages) >= conv.max_history - 2
			@info "We do not cache, because next message is a cut!"
			return nothing
	end
	return :all
end

add_user_message!(conv::ConversationProcessor, user_question::String) = add_user_message!(conv, create_user_message(user_question))
add_user_message!(conv::ConversationProcessor, user_msg::Message) = push!(curr_conv_msgs(conv), user_msg)[end]


add_ai_message!(conv::ConversationProcessor, ai_message::String, meta::Dict) = add_ai_message!(conv, create_AI_message(ai_message, meta))
add_ai_message!(conv::ConversationProcessor, ai_message::String)             = add_ai_message!(conv, create_AI_message(ai_message))
add_ai_message!(conv::ConversationProcessor, ai_msg::Message)                = push!(curr_conv_msgs(conv), ai_msg)[end]
add_error_message!(conv::ConversationProcessor, error_content::String) = begin
	convmes = conv().messages
	isempty(convmes) && return add_user_message!(conv(), error_content)
	return if convmes[end].role == :user 
		add_ai_message!(conv(), error_content)
	elseif convmes[end].role == :assistant 
		update_message_by_id(conv(), convmes[end].id, convmes[end].content * error_content)
	else
		add_user_message!(conv(), error_content)
	end
end



to_dict(conv::ConversationProcessor)                = to_dict(conv())
to_dict_nosys(conv::ConversationProcessor)          = to_dict_nosys(conv())
to_dict_nosys_detailed(conv::ConversationProcessor) = to_dict_nosys_detailed(conv())
to_dict(conv::ConversationInfo)                = [Dict("role" => "system", "content" => conv().system_message); to_dict_nosys(conv())]
to_dict_nosys(conv::ConversationInfo)          = [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
to_dict_nosys_detailed(conv::ConversationInfo) = [to_dict(message) for message in conv.messages]

update_last_user_message_meta(conv::ConversationProcessor, meta) = update_last_user_message_meta(conv(), meta["input_tokens"], meta["output_tokens"], meta["cache_creation_input_tokens"], meta["cache_read_input_tokens"], meta["price"], meta["elapsed"]) 
update_last_user_message_meta(conv::ConversationProcessor, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Float64) = update_last_user_message_meta(conv(), itok, otok, cached, cache_read, price, elapsed)
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
