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
    return [
        SystemMessage(session.system_message.content),
        [msg.role == :user ?      UserMessage(context_combiner!(msg.content, msg.context)) :
         msg.role == :assistant ? AIMessage(  context_combiner!(msg.content, msg.context)) : UserMessage(context_combiner!(msg.content, msg.context))
         for msg in session.messages]...
    ]
end
