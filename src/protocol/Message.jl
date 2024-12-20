
@kwdef mutable struct Message <: MSG
	id::String=short_ulid()
	timestamp::DateTime
	role::Symbol
	content::String
	context::Dict{String,String} = Dict{String,String	}()
	itok::Int=0
	otok::Int=0
	cached::Int=0
	cache_read::Int=0
	price::Float32=0
	elapsed::Float32=0
	stop_sequence::String=""
end

UndefMessage() = Message(timestamp=now(UTC), role=:UNKNOWN, content="")

create_AI_message(ai_message::String, meta::Dict, context::Dict{String,String}=Dict{String,String}()) = Message(timestamp=now(UTC), role=:assistant, content=ai_message, context=context, itok=meta["input_tokens"], otok=meta["output_tokens"], cached=meta["cache_creation_input_tokens"], cache_read=meta["cache_read_input_tokens"], price=meta["price"], elapsed=meta["elapsed"], stop_sequence=get(meta, "stop_sequence", ""))
create_AI_message(ai_message::String)             = Message(timestamp=now(UTC), role=:assistant, content=ai_message)
create_user_message(user_query, context::Dict{String,String}=Dict{String,String}()) = Message(timestamp=now(UTC), role=:user, content=user_query, context=context)


update_message(msg::M, itok, otok, cached, cache_read, price, elapsed) where {M <: MSG} = begin
	msg.itok       = itok
	msg.otok       = otok
	msg.cached     = cached
	msg.cache_read = cache_read
	msg.price      = price
	msg.elapsed    = elapsed
	msg
end

export create_user_message, create_AI_message