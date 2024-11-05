using JSON3

JSON3.StructTypes.StructType(::Type{WebMessage})      = JSON3.StructTypes.Struct()
# JSON3.StructTypes.StructType(::Type{ConversationX})   = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{<:ConversationX}) = JSON3.StructTypes.Mutable()

save_conversation(filepath::String, conv::ConversationX) = write(filepath, JSON3.write(conv))
load_conversation(filepath::String)                      = JSON3.read(read(filepath, String), ConversationX{WebMessage})

