using JSON3

JSON3.StructTypes.StructType(::Type{WebMessage})      = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{<:ConversationX}) = JSON3.StructTypes.Mutable()

save_conversation(filepath::String, conv::ConversationX) = write(filepath, json_pretty(conv) * "\n")
load_conversation(filepath::String)                      = JSON3.read(read(filepath, String), ConversationX{WebMessage})
function json_pretty(obj)
    buf = IOBuffer()
    JSON3.pretty(buf, obj)
    String(take!(buf))
end

