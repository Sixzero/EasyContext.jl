
@kwdef mutable struct Message <: MSG
	id::String=string(uuid4()) #TODO: Check it remove this will it cause issues??
	timestamp::DateTime
	role::Symbol
	content::String
	# example context: Dict("base64img_1" => "image1", "base64img_2" => "image2")
	context::Dict{String, String} = Dict{String, String}()
	itok::Int=0
	otok::Int=0
	cached::Int=0
	cache_read::Int=0
	price::Float32=0
	elapsed::Float32=0
	stop_sequence::String=""
end

UndefMessage() = Message(timestamp=now(UTC), role=:UNKNOWN, content="")

function create_AI_message(ai_message::AbstractString, meta::Dict, context::Dict{String,String}=Dict{String,String}())
    Message(timestamp=now(UTC), role=:assistant, content=ai_message, context=context, itok=meta["input_tokens"], otok=meta["output_tokens"], cached=meta["cache_creation_input_tokens"], cache_read=meta["cache_read_input_tokens"], price=meta["price"], elapsed=meta["elapsed"], stop_sequence=get(meta, "stop_sequence", ""))
end

function create_AI_message(ai_message::AbstractString)
	Message(timestamp=now(UTC), role=:assistant, content=ai_message)
end

function create_user_message(user_query, context::Dict{String,String}=Dict{String,String}())
    Message(timestamp=now(UTC), role=:user, content=user_query, context=context)
end

function create_user_message_with_vectors(user_query; images_base64::Vector{String}=String[], audio_base64::Vector{String}=String[])
	context = Dict{String,String}()
	for (i, img) in enumerate(images_base64)
			context["base64img_$i"] = img
	end
	# for (i, audio) in enumerate(audio_base64)
	# 		context["base64audio_$i"] = audio
	# end
	Message(timestamp=now(UTC), role=:user, content=user_query, context=context)
end

update_message(msg::M, itok, otok, cached, cache_read, price, elapsed) where {M <: MSG} = begin
	msg.itok       = itok
	msg.otok       = otok
	msg.cached     = cached
	msg.cache_read = cache_read
	msg.price      = price
	msg.elapsed    = elapsed
	msg
end

Base.write(io::IO, msg::Message) = println(io, "[$(msg.role)] $(msg.content)")

export create_user_message, create_AI_message