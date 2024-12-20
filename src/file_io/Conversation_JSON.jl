using JSON3

JSON3.StructTypes.StructType(::Type{Message}) = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{<:Session})  = JSON3.StructTypes.Mutable()

save_conversation(filepath::String, conv::Session) = write(filepath, json_pretty(conv) * "\n")
load_conversation(filepath::String) = begin
    json = JSON3.read(read(filepath, String), Dict)
    Session(
        id = json["id"],
        timestamp = DateTime(json["id"]),
        system_message = Message(; 
            id=json["system_message"]["id"],
            timestamp=DateTime(json["system_message"]["timestamp"]),
            role=Symbol(json["system_message"]["role"]),
            content=json["system_message"]["content"],
            itok=json["system_message"]["itok"],
            otok=json["system_message"]["otok"],
            cached=json["system_message"]["cached"],
            cache_read=json["system_message"]["cache_read"],
            price=json["system_message"]["price"],
            elapsed=json["system_message"]["elapsed"]
        ),
        messages = [Message(;
            id=m["id"],
            timestamp=DateTime(m["timestamp"]),
            role=Symbol(m["role"]),
            content=m["content"],
            itok=m["itok"],
            otok=m["otok"],
            cached=m["cached"],
            cache_read=m["cache_read"],
            price=m["price"],
            elapsed=m["elapsed"]
        ) for m in json["messages"]],
        status = Symbol(json["status"])
    )
end

function json_pretty(obj)
    buf = IOBuffer()
    JSON3.pretty(buf, obj)
    String(take!(buf))
end


load_conv(p::PersistableState, conv_id::String) = begin
    filename = get_conversation_filename(p, conv_id)
    isnothing(filename) && return "", String[]
    return filename, load_conv(filename)
end
load_conv(filename::String) = @load filename conv
save_file(p::PersistableState, conv::Session) = save_file(get_conversation_filename(p, conv.id), conv)
save_file(filename::String, conv::Session)    = @save filename conv
