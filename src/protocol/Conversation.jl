using OpenRouter: RunInfo

@kwdef mutable struct Conversation{M <: MSG} <: CONV
    system_message::M
    messages::Vector{M}
end
initConversation(;sys_msg::String) = Conversation(Message(timestamp=now(UTC), role=:system, content=sys_msg), Message[])
initConversation(messages::Vector{M}; sys_msg::String) where M <: Message = Conversation(Message(timestamp=now(UTC), role=:system, content=sys_msg), messages)

(conv::Conversation)(msg::Message) = begin
    if !isempty(conv.messages) && conv.messages[end].role == :assistant && msg.role == :assistant
        conv.messages[end].content *= "\n" * msg.content
        conv
    else
        println("adding message to conversation : $(msg.content)")
        push!(conv.messages, msg)
        conv
    end
end



function cut_history!(conv::CONV; keep=8) # always going to cut after an :assitant but before a :user message.
	length(conv.messages) <= keep && return conv.messages
	start_index = max(1, length(conv.messages) - keep + 1)
	# Adjust forward to the nearest :user message boundary
	while start_index < length(conv.messages) && conv.messages[start_index].role != :user
		start_index += 1
	end
    kept = length(conv.messages) - start_index + 1

	conv.messages = conv.messages[start_index:end]
	kept
end

get_message_by_id(conv::CONV, message_id::String) = findfirst(msg -> msg.id == message_id, conv.messages)
update_message_by_idx(conv::CONV, idx::Int, new_content::String) = ((conv.messages[idx].content = new_content); conv.messages[idx])
update_message_by_id(conv::CONV, message_id::String, new_content::String) = begin
    idx = get_message_by_id(conv, message_id)
    isnothing(idx) && error("Message with id: $message_id not found")
    update_message_by_idx(conv, idx, new_content)
end

# Error handling
function add_error_message!(conv::CONV, error_content::String)
    convmes = conv.messages
    if isempty(convmes)
        push!(convmes, create_user_message(error_content))
    elseif convmes[end].role == :user
        push!(convmes, create_AI_message(error_content))
    elseif convmes[end].role == :assistant
        update_message_by_idx(conv, length(convmes), convmes[end].content * error_content)
    else
        push!(convmes, create_user_message(error_content))
    end
end

function to_dict(conv::CONV)
    [Dict("role" => "system", "content" => conv.system_message.content); to_dict_nosys(conv)]
end
function to_dict_nosys(conv::CONV) 
    [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
end
function to_dict_nosys_detailed(conv::CONV)
    [to_dict(message) for message in conv.messages]
end
# just unwrap it.
# update_last_user_message_meta(conv::CONV, callback::StreamCallbackChannelWrapper) = update_last_user_message_meta(conv, callback.callback)
# function update_last_user_message_meta(conv::CONV, callback::Union{StreamCallbackWithHooks, StreamCallbackWithTokencounts})
#     tokens::TokenCounts, run_info::RunInfo, flavor, model = callback.total_tokens, callback.run_info, callback.flavor, callback.model
#     elapsed = run_info.last_message_time - run_info.creation_time
#     update_last_user_message_meta(conv, tokens.input, tokens.output, tokens.cache_write, tokens.cache_read, OpenRouter.get_cost(flavor, model, tokens), elapsed)
# end
update_last_user_message_meta(conv::CONV, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Number) = update_message(conv.messages[end], itok, otok, cached, cache_read, price, elapsed)

last_msg(conv::CONV) = conv.messages[end].content

get_message_separator(conv_id) = "===AISH_MSG_$(conv_id)==="

function parse_conversation_filename(filename)
    m = match(CONVERSATION_FILE_REGEX, filename)
    return isnothing(m) ? (timestamp=nothing, to_solve="", id="",) : (
        timestamp=date_parse(m[1]),
        to_solve=m[:sent],
        id=m[:id],
    )
end


@kwdef mutable struct TODO <: CONV
    overview::String         # max 20 token thing
end
