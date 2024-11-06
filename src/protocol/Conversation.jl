export Conversation_from_sysmsg

@kwdef mutable struct Conversation{M <: MSG} <: CONV
    system_message::M
    messages::Vector{M}
end

(conv::Conversation)(msg::Message) = (push!(conv.messages, msg); conv)

Conversation(;sys_msg::String) = Conversation(Message(timestamp=now(UTC), role=:system, content=sys_msg), Message[])


function cut_history!(conv::CONV; keep=8) # always going to cut after an :assitant but before a :user message.
	length(conv.messages) <= keep && return conv.messages
	start_index = max(1, length(conv.messages) - keep + 1)
    kept = length(conv.messages) - start_index + 1
	@assert (conv.messages[start_index].role == :user) "how could we cut like this? This function should be only called after :assistant message was attached to the end of the message list"
	
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

to_dict(conv::CONV) = [Dict("role" => "system", "content" => conv.system_message.content); to_dict_nosys(conv)]
to_dict_nosys(conv::CONV) = [Dict("role" => string(msg.role), "content" => msg.content) for msg in conv.messages]
to_dict_nosys_detailed(conv::CONV) = [to_dict(message) for message in conv.messages]

update_last_user_message_meta(conv::CONV, meta) = update_last_user_message_meta(conv, meta["input_tokens"], meta["output_tokens"], meta["cache_creation_input_tokens"], meta["cache_read_input_tokens"], meta["price"], meta["elapsed"])
update_last_user_message_meta(conv::CONV, itok::Int, otok::Int, cached::Int, cache_read::Int, price, elapsed::Number) = update_message(conv.messages[end], itok, otok, cached, cache_read, price, elapsed)

last_msg(conv::CONV) = conv.messages[end].content

@kwdef mutable struct ConversationX{M <: MSG} <: CONV
    id::String = short_ulid()
    timestamp::DateTime = now(UTC)
    system_message::M = UndefMessage()
    messages::Vector{M} = Message[]
    status::Symbol=:PENDING
end
ConversationX(c::Conversation)  = ConversationX(short_ulid(), now(), c.system_message, c.messages, :UNSTARTED)
ConversationX(;sys_msg::String) = ConversationX(Conversation_from_sysmsg(;sys_msg))
(conv::ConversationX)(msg::Message) = (push!(conv.messages, msg); conv)


abs_conversaion_path(p,conv) = joinpath(abspath(expanduser(p.path)), conv.id, "conversations")
conversaion_path(p,conv) = joinpath(p.path, conv.id, "conversations")
conversaion_file(p,conv) = joinpath(conversaion_path(p, conv), "conversation.json")

mkpath_if_missing(path) = isdir(expanduser(path)) || mkdir(expanduser(path))

(p::PersistableState)(conv::ConversationX) = begin
    println(conversaion_path(p, conv))
    mkpath_if_missing(joinpath(p.path, conv.id))
    mkpath_if_missing(conversaion_path(p, conv))
    save_conversation(conversaion_file(p, conv), conv)
    conv
end

get_message_separator(conv_id) = "===AISH_MSG_$(conv_id)==="
get_conversation_filename(p::PersistableState,conv_id::String) = (files = filter(f -> endswith(f, "_$(conv_id).log"), readdir(p.path)); isempty(files) ? nothing : joinpath(p.path, first(files)))

function parse_conversation_filename(filename)
    m = match(CONVERSATION_FILE_REGEX, filename)
    return isnothing(m) ? (timestamp=nothing, to_solve="", id="",) : (
        timestamp=date_parse(m[1]),
        to_solve=m[:sent],
        id=m[:id],
    )
end

load_conv(p::PersistableState, conv_id::String) = begin
    filename = get_conversation_filename(p, conv_id)
    isnothing(filename) && return "", String[]
    return filename, load_conv(filename)
end
load_conv(filename::String) = @load filename conv
save_file(p::PersistableState, conv::String) = save_file(get_conversation_filename(p, conv.id), conv)
save_file(filename::String, conv::ConversationX) = @save filename conv


function generate_overview(conv::CONV, conv_id::String, p::PersistableState)
    @assert false
    sanitized_chars = strip(replace(replace(first(conv.messages[1].content, 32), r"[^\w\s-]" => "_"), r"\s+" => "_"), '_')
    return joinpath(p.path, "$(date_format(conv.timestamp))_$(sanitized_chars)_$(conv_id).log")
end

@kwdef mutable struct TODO <: CONV
    overview::String         # max 20 token thing
end
