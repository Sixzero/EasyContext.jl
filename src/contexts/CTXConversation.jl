export ConversationCTX

@kwdef mutable struct ConversationCTX <: AbstractContextCreator
    conv::Conversation
    max_history::Int = 10
end

ai_stream(conv::ConversationCTX; model, system_msg=conv.conv.system_message, max_tokens::Int=MAX_TOKEN, printout=true, cache=nothing) = ai_stream(conv.conv; system_msg, model, max_tokens, printout, cache)

ConversationCTX_from_sysmsg(;sys_msg::String, max_history=10) = ConversationCTX(
    conv=Conversation(system_message=Message(timestamp=now(UTC), role=:system, content=sys_msg), messages=Message[]),
    max_history=max_history)

(conv::ConversationCTX)(msg::Message) = begin
    push!(conv.conv.messages, msg)
    if length(conv.conv.messages) > conv.max_history
        cut_history!(conv.conv, keep=conv.max_history)
    end
    conv.conv
end

get_cache_setting(conv::ConversationCTX) = begin
    if length(conv.conv.messages) >= conv.max_history - 2
        @info "We do not cache, because next message is a cut!"
        return nothing
    end
    return :all
end

add_error_message!(conv::ConversationCTX, error_content::String) = add_error_message!(conv.conv, error_content)

get_next_msg_contrcutor(conv::ConversationCTX) = get_next_msg_contrcutor(conv.conv)

to_dict(conv::ConversationCTX)                = to_dict(conv.conv)
to_dict_nosys(conv::ConversationCTX)          = to_dict_nosys(conv.conv)
to_dict_nosys_detailed(conv::ConversationCTX) = to_dict_nosys_detailed(conv.conv)

update_last_user_message_meta(conv::AbstractContextCreator, meta) = update_last_user_message_meta(conv.conv, meta["input_tokens"], meta["output_tokens"], meta["cache_creation_input_tokens"], meta["cache_read_input_tokens"], meta["price"], meta["elapsed"]) 
update_last_user_message_meta(conv::AbstractContextCreator, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Number) = update_last_user_message_meta(conv.conv, itok, otok, cached, cache_read, price, elapsed)

export ConversationCTX_from_sysmsg
