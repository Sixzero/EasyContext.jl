
@kwdef mutable struct ToSolve
	id::String=genid()
	timestamp::DateTime=now(UTC)
	to_solve::String=""
	system_message::Union{Message,Nothing}=nothing
	messages::Vector{Message}=[]
end


function cut_history!(conv::ToSolve; keep=13)
	length(conv.messages) <= keep && return conv.messages
	
	start_index = max(1, length(conv.messages) - keep + 1)
	start_index += (conv.messages[start_index].role == :assistant)
	
	conv.messages = conv.messages[start_index:end]
end

get_message_by_id(conv::ToSolve, message_id::String) = findfirst(msg -> msg.id == message_id, conv.messages)

update_message_by_idx(conv::ToSolve, idx::Int, new_content::String) = ((conv.messages[idx].content = new_content); conv.messages[idx])
update_message_by_id(conv::ToSolve, message_id::String, new_content::String) = begin
	idx = get_message_by_id(conv, message_id)
	isnothing(idx) && @assert false "message with the specified id: $id wasnt found! " 
	update_message_by_idx(conv, idx, new_content)
end

add_user_message!(conv::ToSolve, user_question::String) = add_user_message!(conv, create_user_message(user_question))
add_user_message!(conv::ToSolve, user_msg::Message)     = push!(conv.messages, user_msg)[end]

add_ai_message!(conv::ToSolve, ai_message::String, meta::Dict) = add_ai_message!(conv, create_AI_message(ai_message, meta))
add_ai_message!(conv::ToSolve, ai_message::String)             = add_ai_message!(conv, create_AI_message(ai_message))
add_ai_message!(conv::ToSolve, ai_msg::Message)                = push!(conv.messages, ai_msg)[end]

add_error_message!(conv::ToSolve, error_content::String) = begin
	convmes = conv.messages
	isempty(convmes) && return add_user_message!(conv, error_content)
	return if convmes[end].role == :user 
		add_ai_message!(conv, error_content)
	elseif convmes[end].role == :assistant 
		update_message_by_id(conv, convmes[end].id, convmes[end].content * error_content)
	else
		add_user_message!(conv, error_content)
	end
end


to_dict(conv::ToSolve)                = [Dict("role" => "system", "content" => conv().system_message); to_dict_nosys(conv())]
to_dict_nosys(conv::ToSolve)          = [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
to_dict_nosys_detailed(conv::ToSolve) = [to_dict(message) for message in conv.messages]


function update_last_user_message_meta(conv::ToSolve, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Float64)
	msg = conv.messages[end]
	msg.itok       = itok
	msg.otok       = otok
	msg.cached     = cached
	msg.cache_read = cache_read
	msg.price      = price
	msg.elapsed    = elapsed
	msg
end


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

function generate_conversation_filename(conv::ConversationInfo, conversation_id::String)
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


