
JSON3.StructTypes.StructType(::Type{WebMessage})      = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{<:ConversationX}) = JSON3.StructTypes.Struct()

save_conversation(conv::ConversationX, filepath::String) = write(filepath, JSON3.pretty(conv))
load_conversation(filepath::String)                      = JSON3.read(read(filepath, String), ConversationX{WebMessage})
