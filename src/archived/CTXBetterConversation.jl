using Dates
using ..EasyContext: AbstractContextCreator, Conversation, Message, create_AI_message, create_user_message, cut_history!, update_last_user_message_meta

export BetterConversationCTX, BetterConversationCTX_from_sysmsg

@kwdef mutable struct BetterConversationCTX <: AbstractContextCreator
    conv::Conversation
end

(conv::BetterConversationCTX)(msg::Message) = push!(conv.conv.messages, msg)
add_error_message!(conv::BetterConversationCTX, error_content::String) = add_error_message!(conv.conv, error_content)


function BetterConversationCTX_from_sysmsg(;sys_msg::String, max_history=14, cut_to=7)
    BetterConversationCTX(
        conv=Conversation(system_message=Message(timestamp=now(UTC), role=:system, content=sys_msg), messages=Message[]),
        max_history=max_history,
        cut_to=cut_to
    )
end

# Implement other necessary methods for BetterConversationCTX
ai_stream(conv::BetterConversationCTX; model, system_msg=conv.conv.system_message, max_tokens::Int=MAX_TOKEN, printout=true, cache=nothing) = ai_stream(conv.conv; system_msg, model, max_tokens, printout, cache)


get_next_msg_contrcutor(conv::BetterConversationCTX) = get_next_msg_contrcutor(conv.conv)

to_dict(conv::BetterConversationCTX) = to_dict(conv.conv)
to_dict_nosys(conv::BetterConversationCTX) = to_dict_nosys(conv.conv)
to_dict_nosys_detailed(conv::BetterConversationCTX) = to_dict_nosys_detailed(conv.conv)

