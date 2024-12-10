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

(conv::Session)(msg::AIMessage) = begin
    if !isempty(conv.messages) && conv.messages[end].role == :assistant
        conv.messages[end].content *= "\n" * msg.content
        conv
    else
        push!(conv.messages, create_user_message(msg.content))
        conv
    end
end
(conv::Session)(msg::UserMessage) = begin
    if !isempty(conv.messages) && conv.messages[end].role != :assistant
        conv.messages[end].content *= "\n" * msg.content
        conv
    else
        push!(conv.messages, create_AI_message(msg.content))
        conv
    end
end
(conv::Session)(msg::Message) = begin
    if !isempty(conv.messages) && conv.messages[end].role == :assistant && msg.role == :assistant
        conv.messages[end].content *= "\n" * msg.content
        conv
    else
        push!(conv.messages, msg)
        conv
    end
end

abs_conversaion_path(p,conv::Session) = joinpath(abspath(expanduser(p.path)), conv.id, "conversations")
conversaion_path(p,conv::Session) = joinpath(p.path, conv.id, "conversations")
conversaion_file(p,conv::Session) = joinpath(conversaion_path(p, conv), "conversation.json")

(p::PersistableState)(conv::Session) = begin
    println(conversaion_path(p, conv))
    mkpath_if_missing(joinpath(p.path, conv.id))
    mkpath_if_missing(conversaion_path(p, conv))
    save_conversation(conversaion_file(p, conv), conv)
    conv
end
function to_PT_messages(session::Session)
    return [
        SystemMessage(session.system_message.content),
        [msg.role == :user ? UserMessage(msg.content) :
         msg.role == :assistant ? AIMessage(msg.content) : UserMessage(msg.content)
         for msg in session.messages]...
    ]
end
