
bm25_wrapper(context::Context, question::String) = BM25IndexBuilder()(RAGContext(SourceChunk(values(context), keys(context)), question))