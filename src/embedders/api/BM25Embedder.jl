using RAGTools
using SHA

const DTM_CACHE = Dict{String, RAGTools.DocumentTermMatrix}()

@kwdef struct BM25Embedder <: RAGTools.AbstractEmbedder
    processor::RAGTools.AbstractProcessor = RAGTools.KeywordsProcessor()
    normalize=false
end

function get_score(builder::BM25Embedder, chunks::AbstractVector{T}, query::AbstractString; kwargs...) where T
    chunks_str = string.(chunks)
    get_score(builder, chunks_str, query)
end

function get_score(builder::BM25Embedder, chunks::AbstractVector{<:AbstractString}, query::AbstractString; kwargs...)
    key = fast_cache_key(chunks)
    dtm = get!(DTM_CACHE, key) do
        get_dtm_easycontext(builder.processor, chunks)
    end
    
    query_keywords = get_keywords_easycontext(builder.processor, query)
    RAGTools.bm25(dtm, query_keywords, normalize=builder.normalize)
end

get_finder(builder::BM25Embedder) = RAGTools.BM25Similarity()
humanize(e::BM25Embedder) = "BM25"
