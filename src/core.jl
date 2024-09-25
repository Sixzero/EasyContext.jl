abstract type AbstractContextCreator end


function get_cache_setting(::AbstractContextCreator, conv)
	printstyled("WARNING: get_cache_setting not implemented for this contexter type. Defaulting to no caching.\n", color=:red)
	return nothing
end




@kwdef mutable struct Message
	id::String=genid()
	timestamp::DateTime
	role::Symbol
	content::String
	itok::Int=0
	otok::Int=0
	cached::Int=0
	cache_read::Int=0
	price::Float32=0
	elapsed::Float32=0
end

UndefMessage() = Message(id="",timestamp=now(UTC), role=:UNKNOWN, content="")
create_AI_message(ai_message::String, meta::Dict) = Message(id=genid(), timestamp=now(UTC), role=:assistant, content=ai_message, itok=meta["input_tokens"], otok=meta["output_tokens"], cached=meta["cache_creation_input_tokens"], cache_read=meta["cache_read_input_tokens"], price=meta["price"], elapsed=meta["elapsed"])
create_AI_message(ai_message::String)             = Message(id=genid(), timestamp=now(UTC), role=:assistant, content=ai_message)
create_user_message(user_query) = Message(id=genid(), timestamp=now(UTC), role=:user, content=user_query)










@kwdef mutable struct CodeBlock
	id::String = ""  # We'll set this in the constructor
	type::Symbol = :NOTHING
	language::String
	file_path::String
	pre_content::String
	content::String = ""
	run_results::Vector{String} = []
end

# Constructor to set the id based on pre_content hash
function CodeBlock(type::Symbol, language::String, file_path::String, pre_content::String, content::String = "", run_results::Vector{String} = [])
	id = bytes2hex(sha256(pre_content))
	CodeBlock(id, type, language, file_path, pre_content, content, run_results)
end

codestr(cb) = if cb.type==:MODIFY return process_modify_command(cb.file_path, cb.content)
	elseif cb.type==:CREATE         return process_create_command(cb.file_path, cb.content)
	elseif cb.type==:DEFAULT        return cb.content
	else @assert false "not known type for $cb"
end
get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"
process_modify_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
	"meld $(file_path) <(cat <<'$delimiter'\n$(content)\n$delimiter\n)"
end
process_create_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
	"cat > $(file_path) <<'$delimiter'\n$(content)\n$delimiter"
end

preprocess(cb::CodeBlock) = (cb.content = cb.type==:MODIFY ? LLM_apply_changes(cb) : cb.pre_content; cb)

to_dict(cb::CodeBlock)= Dict(
	"id"          => cb.id,
	"type"        => cb.type,
	"language"    => cb.language,
	"file_path"   => cb.file_path,
	"pre_content" => cb.pre_content,
	"content"     => cb.content,
	"run_results" => cb.run_results)


function get_shortened_code(code::String, head_lines::Int=4, tail_lines::Int=3)
	lines = split(code, '\n')
	total_lines = length(lines)
	
	if total_lines <= head_lines + tail_lines
			return code
	else
			head = join(lines[1:head_lines], '\n')
			tail = join(lines[end-tail_lines+1:end], '\n')
			return "$head\n...\n$tail"
	end
end




@kwdef mutable struct ConversationInfo
	id::String=genid()
	timestamp::DateTime=now(UTC)
	sentence::String=""
	system_message::Union{Message,Nothing}=nothing
	messages::Vector{Message}=[]
end


function cut_history!(conv::ConversationInfo; keep=13)
	length(conv.messages) <= keep && return conv.messages
	
	start_index = max(1, length(conv.messages) - keep + 1)
	start_index += (conv.messages[start_index].role == :assistant)
	
	conv.messages = conv.messages[start_index:end]
end

update_message_by_idx(conv::ConversationInfo, idx::Int, new_content::String) = ((conv.messages[idx].content = new_content); conv.messages[idx])
update_message_by_id(conv::ConversationInfo, message_id::String, new_content::String) = begin
	idx = get_message_by_id(conv, message_id)
	isnothing(idx) && @assert false "message with the specified id: $id wasnt found! " 
	update_message_by_idx(conv, idx, new_content)
end
get_message_by_id(conv::ConversationInfo, message_id::String) = findfirst(msg -> msg.id == message_id, conv.messages)