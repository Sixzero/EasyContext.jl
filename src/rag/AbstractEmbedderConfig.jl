using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA


abstract type AbstractRAGPipe end
abstract type AbstractEmbedderConfig end

@kwdef struct BM25EmbedderCombinerConfig <: AbstractEmbedderConfig
    embedding::AbstractEmbedderConfig
    combination_method
    # embedding_model::String = "text-embedding-3-small"
end
JINA_EMBEDDINGS_V2_BASE_CODE = "jina-embeddings-v2-base-code"
@kwdef struct JinaConfig <: AbstractEmbedderConfig
    embedding_model::String = JINA_EMBEDDINGS_V2_BASE_CODE
    top_k::Int = 120
end
@kwdef struct VoyageConfig <: AbstractEmbedderConfig
    embedding_model::String = "voyage-code-2"
    top_k::Int = 120
end
@kwdef struct VoyageCached <: AbstractRAGPipe
    embedding_model::String = "voyage-code-2"
    top_k::Int = 120
    cache::CachedBatchEmbedder
end
VoyageCached(model, top_k) = VoyageCached(;embedding_model=model, top_k, cache=CachedBatchEmbedder(; embedder=VoyageEmbedder()))

@kwdef struct OpenAIEmbeddingConfig <: AbstractEmbedderConfig
    embedding_model::String = "text-embedding-3-small"
    top_k::Int = 120
end

humanize_config(m::BM25EmbedderCombinerConfig) = "Emb. $(m.embedding_model)\ntop_k=$(m.top_k)"
humanize_config(m::JinaConfig) = "Emb. $(m.embedding_model)\ntop_k=$(m.top_k)"
humanize_config(m::VoyageConfig) = "Emb. $(m.embedding_model)\ntop_k=$(m.top_k)"
humanize_config(m::OpenAIEmbeddingConfig) = "Emb. $(m.embedding_model)\ntop_k=$(m.top_k)"

@kwdef struct RerankerConfig <: AbstractEmbedderConfig
    model::String = "claude"
    batch_size::Int = 50
    top_n::Int = 10
    verbose::Int = 1
end

function config2RAG(config::BM25EmbedderCombinerConfig; verbose=false)
    embedder = create_combined_index_builder(config.embedding_model; top_k=config.top_k)
    EmbedderSearch(embedder, config)
end

function config2RAG(config::JinaConfig; verbose=false, cache_prefix="")
    embedder = create_jina_embedder(model=config.embedding_model, top_k=config.top_k; cache_prefix)
    EmbedderSearch(embedder, config)
end

function config2RAG(config::VoyageConfig; verbose=false)
    embedder = create_voyage_embedder(model=config.embedding_model, top_k=config.top_k)
    EmbedderSearch(embedder, config)
end

function config2RAG(config::OpenAIEmbeddingConfig; verbose=false, cache_prefix="")
    embedder = create_openai_embedder(model=config.embedding_model, top_k=config.top_k; cache_prefix)
    EmbedderSearch(embedder, config)
end

function config2RAG(embedder_config::AbstractEmbedderConfig, reranker_config::AbstractEmbedderConfig; verbose=false)
    EmbeddingSearchReranker(embedder_config, reranker_config)
end

mutable struct EmbedderSearch{T}
    config::Union{BM25EmbedderCombinerConfig, JinaConfig, VoyageConfig, OpenAIEmbeddingConfig}
    embedder::T
    
    function EmbedderSearch(config::Union{BM25EmbedderCombinerConfig, JinaConfig, VoyageConfig, OpenAIEmbeddingConfig})
        embedder = config2RAG(config)
        new{typeof(embedder)}(config, embedder)
    end
end

# Direct chunks-based search
function similarity_search(searcher::EmbedderSearch, chunks::AbstractVector{T}, query) where T
    score = get_score(searcher, chunks, query)
    topN(score, chunks, searcher.config.top_n)
end
function get_score(builder::EmbedderSearch, chunks::AbstractVector{T}, query::AbstractString, similarity::Val{S}=Val(RAG.CosineSimilarity()); cost_tracker = Threads.Atomic{Float64}(0.0)) where {T, S}
    embeddings = RAG.get_embeddings(builder.embedder, chunks; cost_tracker)
    query_emb = RAG.get_embeddings(builder.embedder, [query]; cost_tracker)
    get_score(similarity, embeddings, reshape(query_emb, :))
end
function get_score(
    finder::Val{RAG.CosineSimilarity}, emb::AbstractMatrix{<:Real}, query_emb::AbstractVector{<:Real})
    # emb is an embedding matrix where the first dimension is the embedding dimension
    query_emb' * emb |> vec
end

get_embedder(builder::EmbedderSearch) = builder.embedder

function cache_key(builder::EmbedderSearch, args...)
    embedder_type = typeof(get_embedder(builder)).name.name
    model_name = get_model_name(builder.embedder)
    hash_str = hash("$(args)_$(embedder_type)_$(model_name)")
    return bytes2hex(sha256("EmbedderSearch_$hash_str"))
end

export EmbedderSearch

