export Session, initSession

@kwdef mutable struct Session{M <: MSG} <: CONV
    id::String = short_ulid()
    timestamp::DateTime = now(UTC)
    messages::Vector{M} = Message[]
    status::Symbol = :PENDING
end
# Session(c::Conversation) = Session(short_ulid(), now(), c.messages, :UNSTARTED)
initSession(messages::Vector{M};sys_msg::String="") where M <: Message = Session(initConversation(messages; sys_msg))

function push_message!(conv::Session, msg::AIMessage, stop_sequence::String="")
    if !isempty(conv.messages) && conv.messages[end].role == :assistant
        conv.messages[end].content *= "\n" * msg.content * stop_sequence
    else
        push!(conv.messages, create_AI_message(String(msg.content)))
    end
    conv
end

function push_message!(conv::Session, msg::UserMessage)
    if !isempty(conv.messages) && conv.messages[end].role != :assistant
        conv.messages[end].content *= "\n" * msg.content
    else
        push!(conv.messages, create_user_message(String(msg.content)))
    end
    conv
end

function push_message!(conv::Session, msg::Message, stop_sequence::String="")
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

is_image_path(word::AbstractString) = occursin(r"[\"']([^\"']*?\.(?:png|jpg|jpeg|gif|bmp))[\"']", word)
extract_image_paths(content::AbstractString) = [m.captures[1] for m in eachmatch(r"[\"']([^\"']*?\.(?:png|jpg|jpeg|gif|bmp))[\"']", content)]

function to_PT_messages(session::Session, sys_msg::String)
    messages = Vector{PT.AbstractChatMessage}(undef, length(session.messages) + 1)
    messages[1] = SystemMessage(sys_msg)
    
    for (i, msg) in enumerate(session.messages)
        full_content = context_combiner!(msg.content, msg.context)
        messages[i + 1] = if msg.role == :user
            image_paths = extract_image_paths(msg.content)
            isempty(image_paths) ? UserMessage(full_content) : PT.UserMessageWithImages(full_content; image_path=image_paths)
        elseif msg.role == :assistant 
            AIMessage(full_content)
        else
            UserMessage(full_content)
        end
    end
    return messages
end