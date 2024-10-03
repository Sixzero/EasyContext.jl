using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: AbstractReranker
using DataStructures: OrderedDict

struct RerankGPTPro <: AbstractReranker
    model::String
    batch_size::Int
    top_n::Int
end

function (reranker::RerankGPTPro)(chunks::OrderedDict{String,String}, question::String)
    reranked_indices = RAG.rerank(ReduceRankGPTReranker(batch_size=reranker.batch_size, model=reranker.model), 
                                  collect(values(chunks)), question; top_n=reranker.top_n)
    sources = collect(keys(chunks))
    contexts = collect(values(chunks))
    new_sources = sources[reranked_indices]
    new_contexts = contexts[reranked_indices]
    return OrderedDict(zip(new_sources, new_contexts))
end

export RerankGPTPro
