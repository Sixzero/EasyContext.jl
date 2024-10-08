export Conversation_from_sysmsg

@kwdef mutable struct Conversation{M <: MSG} <: CONV
    system_message::M
    messages::Vector{M}
end

(conv::CONV)(msg::Message) = push!(conv.messages, msg)

Conversation_from_sysmsg(;sys_msg::String) = Conversation(Message(timestamp=now(UTC), role=:system, content=sys_msg), Message[])


function cut_history!(conv::CONV; keep=8) # always going to cut after an :assitant but before a :user message.
	length(conv.messages) <= keep && return conv.messages
	start_index = max(1, length(conv.messages) - keep + 1)
	@assert (conv.messages[start_index].role == :user) "how could we cut like this? This function should be only called after :assistant message was attached to the end of the message list"
	
	conv.messages = conv.messages[start_index:end]
	keep
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

@kwdef mutable struct ToSolve{M <: MSG} <: CONV
    id::String = genid()
    timestamp::DateTime = now(UTC)
    overview::String = ""
    system_message::M = UndefMessage()
    messages::Vector{M} = Message[]
end
ToSolve_from_sysmsg(;sys_msg::String) = ToSolve(Conversation_from_sysmsg(;sys_msg))

ToSolve(c::Conversation) = ToSolve(genid(), now(), "", c.system_message, c.messages)


get_message_separator(tosolve_id) = "===AISH_MSG_$(tosolve_id)==="
get_conversation_filename(p::PersistableState,tosolve_id) = (files = filter(f -> endswith(f, "_$(tosolve_id).log"), readdir(CONVERSATION_DIR(p))); isempty(files) ? nothing : joinpath(CONVERSATION_DIR(p), first(files)))

function parse_conversation_filename(filename)
    m = match(CONVERSATION_FILE_REGEX, filename)
    return isnothing(m) ? (timestamp=nothing, to_solve="", id="",) : (
        timestamp=date_parse(m[1]),
        to_solve=m[:sent],
        id=m[:id],
    )
end

load_tosolve(p::PersistableState, tosolve_id::String) = begin
    filename = get_conversation_filename(p, tosolve_id)
    isnothing(filename) && return "", String[]
    return filename, load_tosolve(filename)
end
load_tosolve(filename::String) = @load filename tosolve
save_file(filename::String, tosolve::ToSolve) = @save filename tosolve


function generate_overview(conv::CONV, tosolve_id::String)
	sanitized_chars = strip(replace(replace(first(conv.messages[1].content, 32), r"[^\w\s-]" => "_"), r"\s+" => "_"), '_')
	return joinpath(CONVERSATION_DIR, "$(date_format(conv.timestamp))_$(sanitized_chars)_$(tosolve_id).log")
end


