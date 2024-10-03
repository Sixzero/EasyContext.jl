using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractReranker
using DataStructures: OrderedDict

struct CohereRerankPro <: AbstractReranker
    model::String
    top_n::Int
end

function (reranker::CohereRerankPro)(chunks::OrderedDict{String,String}, question::String)
    reranked_indices = RAG.rerank(RAG.CohereReranker(model=reranker.model), question, collect(values(chunks)); top_n=reranker.top_n)
    sources = collect(keys(chunks))
    contexts = collect(values(chunks))
    new_sources = sources[reranked_indices]
    new_contexts = contexts[reranked_indices]
    return OrderedDict(zip(new_sources, new_contexts))
end

export CohereRerankPro
