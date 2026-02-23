using OpenRouter: AbstractMessage, SystemMessage, UserMessage, AIMessage, ToolMessage
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

function push_message!(conv::Session, msg::AIMessage)
    if !isempty(conv.messages) && conv.messages[end].role == :assistant && msg.tool_calls === nothing
        conv.messages[end].content *= "\n" * msg.content
    else
        push!(conv.messages, create_AI_message(String(msg.content); tool_calls=msg.tool_calls))
    end
    conv
end

function push_message!(conv::Session, msg::ToolMessage)
    images = isnothing(msg.image_data) ? String[] : msg.image_data
    push!(conv.messages, create_tool_message(String(msg.content), msg.tool_call_id; images_base64=images))
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

function push_message!(conv::Session, msg::Message)
    if !isempty(conv.messages) && conv.messages[end].role == :assistant && msg.role == :assistant
        conv.messages[end].content *= "\n" * msg.content
    else
        push!(conv.messages, msg)
    end
    conv
end

abs_conversation_path(p,conv::Session) = joinpath(abspath(expanduser(path)), conv.id, "conversations")
conversation_path(path,conv::Session) = joinpath(path, conv.id, "conversations")
conversation_file(path,conv::Session) = joinpath(conversation_path(path, conv), "conversation.json")


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
        elseif msg.role == :tool
            image_keys = sort(filter(k -> startswith(k, "base64img_"), collect(keys(msg.context))))
            image_data = isempty(image_keys) ? nothing : [msg.context[k] for k in image_keys]
            ToolMessage(content=msg.content, tool_call_id=msg.tool_call_id, image_data=image_data)
        elseif msg.role == :assistant
            full_content = context_combiner!(msg.content, msg.context)
            AIMessage(content=full_content, tool_calls=msg.tool_calls)
        else
            full_content = context_combiner!(msg.content, msg.context)
            UserMessage(content=full_content)
        end
    end

    # Fallback: ensure every tool_use has a matching tool_result.
    # If attachments didn't arrive (e.g., deny path, network issues), the API
    # will reject the request. Inject placeholder tool_results for any orphaned tool_use ids.
    ensure_tool_results!(messages)

    return messages
end

"""
    ensure_tool_results!(messages)

Scan messages for assistant tool_calls without matching ToolMessages and inject
placeholder tool_results so the LLM API doesn't reject the request.
"""
function ensure_tool_results!(messages::Vector{AbstractMessage})
    # The API requires that every tool_use in an AIMessage has a matching tool_result
    # in the IMMEDIATELY FOLLOWING message(s). This function ensures that by:
    # 1. Moving misplaced tool_results (found later in conversation) to the correct position
    # 2. Injecting placeholders for completely missing tool_results

    modified = true
    while modified
        modified = false
        for i in 1:length(messages)
            msg = messages[i]
            msg isa AIMessage || continue
            msg.tool_calls === nothing && continue

            needed_ids = Set(tc["id"] for tc in msg.tool_calls)
            isempty(needed_ids) && continue

            # Check which tool_results are already correctly placed (immediately after this AIMessage)
            j = i + 1
            while j <= length(messages) && messages[j] isa ToolMessage
                delete!(needed_ids, messages[j].tool_call_id)
                j += 1
            end

            isempty(needed_ids) && continue

            # For each missing id: look for a misplaced ToolMessage later, or create placeholder
            insert_at = j  # insert right after the last correctly-placed ToolMessage (or after AIMessage)
            offset = 0
            for id in collect(needed_ids)
                # Search for this tool_result later in the conversation
                found_idx = nothing
                for k in j:length(messages)
                    if messages[k] isa ToolMessage && messages[k].tool_call_id == id
                        found_idx = k
                        break
                    end
                end

                if found_idx !== nothing
                    # Move misplaced tool_result to correct position
                    tool_msg = messages[found_idx]
                    deleteat!(messages, found_idx)
                    insert!(messages, insert_at + offset, tool_msg)
                    @warn "Relocated misplaced tool_result to correct position" tool_call_id=id from=found_idx to=insert_at+offset
                else
                    # No tool_result anywhere — inject placeholder
                    insert!(messages, insert_at + offset, ToolMessage(
                        content="[This tool call did not produce a result before the conversation continued.]",
                        tool_call_id=id
                    ))
                    @warn "Injected placeholder tool_result" tool_call_id=id at=insert_at+offset
                end
                offset += 1
            end
            modified = true
            break  # restart scan since indices shifted
        end
    end
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