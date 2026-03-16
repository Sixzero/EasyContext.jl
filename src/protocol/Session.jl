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

Ensure tool_use/tool_result consistency:
1. Missing tool_results → inject placeholder
2. Misplaced tool_results (separated from their tool_use by other messages) → relocate them
3. Orphaned tool_results (no matching tool_use, e.g. after compaction) → remove them
"""
function ensure_tool_results!(messages::Vector{AbstractMessage})
    # Build map: tool_call_id → AIMessage index
    tc_to_ai = Dict{String, Int}()
    # Build map: tool_call_id → ToolMessage index (if exists)
    tc_to_tool = Dict{String, Int}()

    for (i, msg) in enumerate(messages)
        if msg isa AIMessage && msg.tool_calls !== nothing
            for tc in msg.tool_calls
                tc_to_ai[tc["id"]] = i
            end
        elseif msg isa ToolMessage
            tc_to_tool[msg.tool_call_id] = i
        end
    end

    # Case 3: Remove orphaned tool_results (ToolMessages with no matching tool_use).
    # This happens when compaction removes an AIMessage but its ToolMessages survive.
    orphaned_tool_ids = [id for id in keys(tc_to_tool) if !haskey(tc_to_ai, id)]
    if !isempty(orphaned_tool_ids)
        @warn "Removing orphaned tool_results (no matching tool_use)" ids=orphaned_tool_ids
        orphaned_set = Set(orphaned_tool_ids)
        filter!(m -> !(m isa ToolMessage && m.tool_call_id in orphaned_set), messages)
        # Rebuild tc_to_tool after removal
        empty!(tc_to_tool)
        for (i, msg) in enumerate(messages)
            msg isa ToolMessage && (tc_to_tool[msg.tool_call_id] = i)
        end
    end

    # Find tool_calls whose tool_result is missing or misplaced.
    # "Correctly placed" = the ToolMessage appears in the contiguous block of
    # ToolMessages right after the AIMessage (before any non-ToolMessage).
    misplaced_ids = String[]
    orphaned_ids  = String[]

    for (id, ai_idx) in tc_to_ai
        if !haskey(tc_to_tool, id)
            push!(orphaned_ids, id)
        else
            tool_idx = tc_to_tool[id]
            # Check if tool_idx is in the contiguous ToolMessage block after ai_idx
            # Valid range: ai_idx+1 .. first non-ToolMessage after ai_idx
            is_placed = false
            for j in (ai_idx + 1):length(messages)
                messages[j] isa ToolMessage || break
                j == tool_idx && (is_placed = true; break)
            end
            is_placed || push!(misplaced_ids, id)
        end
    end

    if isempty(orphaned_ids) && isempty(misplaced_ids)
        return
    end

    !isempty(orphaned_ids)  && @warn "Injecting placeholder tool_results for orphaned tool_use ids" ids=orphaned_ids
    !isempty(misplaced_ids) && @warn "Relocating misplaced tool_results to follow their tool_use" ids=misplaced_ids

    # Remove misplaced ToolMessages (iterate in reverse to preserve indices)
    relocated = Dict{String, ToolMessage}()
    for id in misplaced_ids
        idx = tc_to_tool[id]
        relocated[id] = messages[idx]
    end
    filter!(m -> !(m isa ToolMessage && m.tool_call_id in misplaced_ids), messages)

    # Now rebuild tc_to_ai with current indices (after removals)
    tc_to_ai_new = Dict{String, Int}()
    for (i, msg) in enumerate(messages)
        if msg isa AIMessage && msg.tool_calls !== nothing
            for tc in msg.tool_calls
                tc_to_ai_new[tc["id"]] = i
            end
        end
    end

    # Collect all ids that need insertion, grouped by AIMessage index
    all_insert = Dict{Int, Vector{Tuple{String, ToolMessage}}}()
    for id in orphaned_ids
        ai_idx = tc_to_ai_new[id]
        entry = get!(all_insert, ai_idx, Tuple{String, ToolMessage}[])
        push!(entry, (id, ToolMessage(content="[This tool call did not produce a result before the conversation continued.]", tool_call_id=id)))
    end
    for id in misplaced_ids
        ai_idx = tc_to_ai_new[id]
        entry = get!(all_insert, ai_idx, Tuple{String, ToolMessage}[])
        push!(entry, (id, relocated[id]))
    end

    # Insert after each AIMessage, in reverse index order to preserve positions
    for ai_idx in sort(collect(keys(all_insert)), rev=true)
        # Find insertion point: after the last consecutive ToolMessage following ai_idx
        insert_at = ai_idx + 1
        while insert_at <= length(messages) && messages[insert_at] isa ToolMessage
            insert_at += 1
        end
        for (_, tool_msg) in reverse(all_insert[ai_idx])
            insert!(messages, insert_at, tool_msg)
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