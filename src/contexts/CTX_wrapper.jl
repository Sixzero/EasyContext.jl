
CTX_wrapper(context::Context, question::String) = (RAGContext(SourceChunk(values(context), keys(context)), question))
CTX_unwrapp(source, context) = Dict(s=>c for (s,c) in zip(source, context))


