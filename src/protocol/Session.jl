using OpenRouter: AbstractMessage, SystemMessage, UserMessage, AIMessage
export Session, initSession

include("SessionImageSupport.jl")

@kwdef mutable struct Session{M <: MSG} <: CONV
    id::String = string(uuid4()) #TODO: Check it if we don't use it then will it cause issues?
    timestamp::DateTime = now(UTC)
    messages::Vector{M} = Message[]
    status::Symbol = :PENDING
end
# Session(c::Conversation) = Session(uuid4(), now(), c.messages, :UNSTARTED)
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
    
    messages = Vector{AbstractMessage}(undef, length(session.messages) + 1)
    messages[1] = SystemMessage(content=sys_msg)
    
    for (i, msg) in enumerate(session.messages)
        messages[i + 1] = if msg.role == :user
            # Extract file paths from content
            image_paths = imagepaths_in_messages_supported ? validate_image_paths(extract_image_paths(msg.content)) : String[]
            
            # Extract base64 images from context - check both key naming and data:image prefix
            base64_images = filter(p -> startswith(p.first, "base64img_") || startswith(p.second, "data:image"), collect(msg.context))
            base64_urls = isempty(base64_images) ? String[] : [p.second for p in base64_images]
            
            # Combine content with context
            full_content = context_combiner!(msg.content, msg.context, false)
            
            # Create OpenRouter UserMessage with image data
            if !isempty(image_paths) || !isempty(base64_urls)
                # Convert file paths to data URLs if needed
                all_image_data = String[]
                for path in image_paths
                    if isfile(path)
                        # Convert file to data URL (you may need to implement this helper)
                        push!(all_image_data, file_to_data_url(path))
                    end
                end
                append!(all_image_data, base64_urls)
                
                UserMessage(content=full_content, image_data=all_image_data)
            else
                UserMessage(content=full_content)
            end
        elseif msg.role == :assistant 
            full_content = context_combiner!(msg.content, msg.context)
            AIMessage(content=full_content)
        else
            full_content = context_combiner!(msg.content, msg.context)
            UserMessage(content=full_content)
        end
    end
    return messages
end

# Helper function to convert file path to data URL (add this if not exists)
function file_to_data_url(filepath::String)
    if !isfile(filepath)
        return ""
    end
    
    # Determine MIME type based on extension
    ext = lowercase(splitext(filepath)[2])
    mime_type = if ext == ".jpg" || ext == ".jpeg"
        "image/jpeg"
    elseif ext == ".png"
        "image/png"
    elseif ext == ".gif"
        "image/gif"
    elseif ext == ".webp"
        "image/webp"
    else
        "image/jpeg"  # default
    end
    
    # Read file and encode as base64
    data = read(filepath)
    b64_data = base64encode(data)
    
    return "data:$mime_type;base64,$b64_data"
end