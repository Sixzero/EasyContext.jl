using RAGTools
import RAGTools as RAG
using SHA

const DTM_CACHE = Dict{String, RAG.DocumentTermMatrix}()

@kwdef struct BM25Embedder <: AbstractEmbedder
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
    normalize=false
end

function get_score(builder::BM25Embedder, chunks::AbstractVector{T}, query::AbstractString; kwargs...) where T
    chunks_str = string.(chunks)
    get_score(builder, chunks_str, query)
end

function get_score(builder::BM25Embedder, chunks::AbstractVector{<:AbstractString}, query::AbstractString; kwargs...)
    key = fast_cache_key(chunks)
    dtm = get!(DTM_CACHE, key) do
        get_dtm(builder.processor, chunks)
    end
    
    query_keywords = get_keywords(builder.processor, query)
    RAG.bm25(dtm, query_keywords, normalize=builder.normalize)
end

get_finder(builder::BM25Embedder) = RAG.BM25Similarity()
humanize(e::BM25Embedder) = "BM25"
