export Conversation_from_sysmsg

@kwdef mutable struct Conversation{M <: MSG} <: CONV
	system_message::M
	messages::Vector{M}=[]
end

(conv::Conversation)(msg::Message) = push!(conv.messages, msg)

Conversation_from_sysmsg(;sys_msg::String) = Conversation(system_message=Message(timestamp=now(UTC), role=:system, content=sys_msg), messages=Message[])

# always going to cut after an :assitant but before a :user message.
function cut_history!(conv::Conversation; keep=8)
	length(conv.messages) <= keep && return conv.messages
	# keep = conv.messages[length(conv.messages) - keep].role == :user ? keep + 1 : keep
	start_index = max(1, length(conv.messages) - keep + 1)
	@assert (conv.messages[start_index].role == :user) "how could we cut like this? This function should be only called after :assistant message was attached to the end of the message list"
	
	conv.messages = conv.messages[start_index:end]
	keep
end

get_message_by_id(conv::Conversation, message_id::String) = findfirst(msg -> msg.id == message_id, conv.messages)

update_message_by_idx(conv::Conversation, idx::Int, new_content::String) = ((conv.messages[idx].content = new_content); conv.messages[idx])
update_message_by_id(conv::Conversation, message_id::String, new_content::String) = begin
	idx = get_message_by_id(conv, message_id)
	isnothing(idx) && @assert false "message with the specified id: $id wasnt found! " 
	update_message_by_idx(conv, idx, new_content)
end


add_error_message!(conv::Conversation, error_content::String) = begin
	convmes = conv.messages
	isempty(convmes) && return push!(convmes, create_user_message(error_content))
	if convmes[end].role == :user
		push!(convmes, create_AI_message(error_content))
	elseif convmes[end].role == :assistant 
		update_message_by_idx(conv, length(convmes), convmes[end].content * error_content)
	else
		push!(convmes, create_user_message(error_content))
	end
end


to_dict(conv::Conversation)                = [Dict("role" => "system", "content" => conv.system_message); to_dict_nosys(conv)]
to_dict_nosys(conv::Conversation)          = [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
to_dict_nosys_detailed(conv::Conversation) = [to_dict(message) for message in conv.messages]

update_last_user_message_meta(conv::Conversation, meta) = update_last_user_message_meta(conv, meta["input_tokens"], meta["output_tokens"], meta["cache_creation_input_tokens"], meta["cache_read_input_tokens"], meta["price"], meta["elapsed"]) 
update_last_user_message_meta(conv::Conversation, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Number) = update_message(conv.messages[end], itok, otok, cached, cache_read, price, elapsed)


get_all_conversations_file(p) = readdir(CONVERSATION_DIR(p))
get_message_separator(conversation_id) = "===AISH_MSG_$(conversation_id)==="
get_conversation_filename(conversation_id) = (files = filter(f -> endswith(f, "_$(conversation_id).log"), readdir(CONVERSATION_DIR)); isempty(files) ? nothing : joinpath(CONVERSATION_DIR, first(files)))

function parse_conversation_filename(filename)
    m = match(CONVERSATION_FILE_REGEX, filename)
    return isnothing(m) ? (timestamp=nothing, to_solve="", id="") : (
        timestamp=date_parse(m[1]),
        to_solve=m[:sent],
        id=m[:id]
    )
end

function generate_conversation_filename(conv::Conversation, conversation_id::String)
    sanitized_chars = strip(replace(replace(first(conv.messages[1].content, 32), r"[^\w\s-]" => "_"), r"\s+" => "_"), '_')
    return joinpath(CONVERSATION_DIR, "$(date_format(conv.timestamp))_$(sanitized_chars)_$(conversation_id).log")
end

function read_conversation_file(conversation_id)
    filename = get_conversation_filename(conversation_id)
    isnothing(filename) && return "", String[]

    content = read(filename, String)
    messages = split(content, get_message_separator(conversation_id), keepempty=false)

    return filename, messages
end

function save_file(filepath::String, content::String)
    open(filepath, "w") do file
        write(file, content)
    end
    return true
end

function get_next_msg_contrcutor(conv::Conversation)
    isempty(conv.messages) && return create_user_message
    return conv.messages[end].role === :user ? create_AI_message : create_user_message
end


@kwdef mutable struct WebConversation <: CONV
	id::String=genid()
	timestamp::DateTime=now(UTC)
	to_solve::String=""
	system_message::WebMessage
	messages::Vector{WebMessage}=[]
end

