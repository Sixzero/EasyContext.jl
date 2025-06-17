export Session, initSession
include("SessionImageSupport.jl")

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


function to_PT_messages(session::Session, sys_msg::String, imagepaths_in_messages_supported::Bool=false)
    messages = Vector{PT.AbstractChatMessage}(undef, length(session.messages) + 1)
    messages[1] = SystemMessage(sys_msg)
    
    for (i, msg) in enumerate(session.messages)
        messages[i + 1] = if msg.role == :user
            # Extract file paths from content
            image_paths = imagepaths_in_messages_supported ? validate_image_paths(extract_image_paths(msg.content)) : String[]
            
            # Extract base64 images from context
            base64_images = filter(p -> startswith(p.first, "base64img_"), msg.context)
            base64_urls = isempty(base64_images) ? nothing : collect(values(base64_images))
            
            if !isempty(image_paths) || !isempty(base64_images)
                # Use the existing constructor which handles both paths and base64
                new_content = context_combiner!(msg.content, msg.context, false)
                PT.UserMessageWithImages(new_content; 
                    image_path = isempty(image_paths) ? nothing : image_paths,
                    image_url = base64_urls)
            else
                full_content = context_combiner!(msg.content, msg.context)
                UserMessage(full_content)
            end
        elseif msg.role == :assistant 
            AIMessage(full_content)
        else
            UserMessage(full_content)
        end
    end
    return messages
end