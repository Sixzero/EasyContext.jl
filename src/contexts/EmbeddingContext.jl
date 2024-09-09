using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: SimpleIndexer
using JLD2

function get_embedding_context(index::RAG.AbstractChunkIndex, question::String)
    rephraser = JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model="claude", verbose=true)
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    retriever = RAG.AdvancedRetriever(;
        finder=RAG.CosineSimilarity(), 
        reranker, 
        rephraser
    )
    
    result = RAG.retrieve(retriever, index, question; 
        return_all=true,
        embedder_kwargs = (; model = "text-embedding-3-small"),
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), index, result)
    
    return result
end

