export Session, initSession

@kwdef mutable struct Session{M <: MSG} <: CONV
    id::String = short_ulid()
    timestamp::DateTime = now(UTC)
    system_message::M = UndefMessage()
    messages::Vector{M} = Message[]
    status::Symbol = :PENDING
end
Session(c::Conversation) = Session(short_ulid(), now(), c.system_message, c.messages, :UNSTARTED)
initSession(;sys_msg::String="") = Session(initConversation(;sys_msg))
initSession(messages::Vector{M};sys_msg::String="") where M <: Message = Session(initConversation(messages; sys_msg))

(conv::Session)(msg::AIMessage, stop_sequence::String="") = begin
    if !isempty(conv.messages) && conv.messages[end].role == :assistant
        conv.messages[end].content *= "\n" * msg.content * stop_sequence
    else
        push!(conv.messages, create_AI_message(String(msg.content)))
    end
    conv
end
(conv::Session)(msg::UserMessage) = begin
    if !isempty(conv.messages) && conv.messages[end].role != :assistant
        conv.messages[end].content *= "\n" * msg.content
    else
        push!(conv.messages, create_user_message(String(msg.content)))
    end
    conv
end
(conv::Session)(msg::Message, stop_sequence::String="") = begin
    if !isempty(conv.messages) && conv.messages[end].role == :assistant && msg.role == :assistant
        conv.messages[end].content *= "\n" * msg.content * stop_sequence
    else
        push!(conv.messages, msg)
    end
    conv
end

abs_conversaion_path(p,conv::Session) = joinpath(abspath(expanduser(path)), conv.id, "conversations")
conversaion_path(path,conv::Session) = joinpath(path, conv.id, "conversations")
conversaion_file(path,conv::Session) = joinpath(conversaion_path(path, conv), "conversation.json")

function to_PT_messages(session::Session)
    messages = Vector{PT.AbstractChatMessage}(undef, length(session.messages) + 1)
    messages[1] = SystemMessage(session.system_message.content)
    
    for (i, msg) in enumerate(session.messages)
        content = context_combiner!(msg.content, msg.context)
        messages[i + 1] = if msg.role == :user
            UserMessage(content)
        elseif msg.role == :assistant 
            AIMessage(content)
        else
            UserMessage(content)
        end
    end
    return messages
end