
CTX_wrapper(context::Context, question::String) = RAGContext(SourceChunk(collect(keys(context)), collect(values(context))), question)
CTX_unwrapp(r::RAGContext)   = CTX_unwrapp(r.chunk.sources, r.chunk.contexts)
CTX_unwrapp(source, context) = Dict(s=>c for (s,c) in zip(source, context))


