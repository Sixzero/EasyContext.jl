

@kwdef mutable struct ConversationProcessor
	conv::Conversation
	max_history::Int = 10
end

Anthropic.ai_stream_safe(conv::ConversationProcessor; model, system_msg=conv().system_message, max_tokens::Int=MAX_TOKEN, printout=true, cache=nothing) = ai_stream_safe(conv(); system_msg, model, max_tokens, printout, cache)

ConversationProcessorr(;sys_msg::String) = ConversationProcessor(
	conv=Conversation(system_message=Message(id=genid(), timestamp=now(UTC), role=:system, content=sys_msg)),
	max_history=10)
	
(conv::ConversationProcessor)() = conv.conv


save!(conv::ConversationProcessor, msg::Message) =  begin
	push!(conv().messages, msg)
	if length(conv().messages) > conv.max_history
			cut_history!(conv(), keep=conv.max_history)
	end
	return msg
end


get_cache_setting(conv::ConversationProcessor) = begin
	if length(conv().messages) >= conv.max_history - 2
			@info "We do not cache, because next message is a cut!"
			return nothing
	end
	return :all
end


add_user_message!(conv::ConversationProcessor, user_question::String) = add_user_message!(conv(), user_question)
add_user_message!(conv::ConversationProcessor, user_msg::Message)     = add_user_message!(conv(), user_msg)

add_ai_message!(conv::ConversationProcessor, ai_message::String, meta::Dict) = add_ai_message!(conv(), create_AI_message(ai_message, meta))
add_ai_message!(conv::ConversationProcessor, ai_message::String)             = add_ai_message!(conv(), create_AI_message(ai_message))
add_ai_message!(conv::ConversationProcessor, ai_msg::Message)                = add_ai_message!(conv(), ai_msg)

add_error_message!(conv::ConversationProcessor, error_content::String)       = add_error_message!(conv(), error_content)


to_dict(conv::ConversationProcessor)                = to_dict(conv())
to_dict_nosys(conv::ConversationProcessor)          = to_dict_nosys(conv())
to_dict_nosys_detailed(conv::ConversationProcessor) = to_dict_nosys_detailed(conv())

update_last_user_message_meta(conv::ConversationProcessor, meta) = update_last_user_message_meta(conv(), meta["input_tokens"], meta["output_tokens"], meta["cache_creation_input_tokens"], meta["cache_read_input_tokens"], meta["price"], meta["elapsed"]) 
update_last_user_message_meta(conv::ConversationProcessor, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Float64) = update_last_user_message_meta(conv(), itok, otok, cached, cache_read, price, elapsed)
