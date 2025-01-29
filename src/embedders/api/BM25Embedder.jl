using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA

# I think we will need a normalized BM25 score, so we can use it with other scores
@kwdef mutable struct BM25Embedder <: AbstractEmbedder
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
end

function get_score(builder::BM25Embedder, chunks::AbstractVector{T}, query::AbstractString) where T
    chunks_str = string.(chunks)
    get_score(builder, chunks_str, query)
end
function get_score(builder::BM25Embedder, chunks::AbstractVector{<:AbstractString}, query::AbstractString)
    dtm = get_dtm(builder.processor, chunks)
    query_keywords = get_keywords(builder.processor, query)
    RAG.bm25(dtm, query_keywords)
end

function get_finder(builder::BM25Embedder)
    RAG.BM25Similarity()
end

# Add humanize method
humanize(e::BM25Embedder) = "BM25"
