
using PromptingTools.Experimental.RAGTools: BatchEmbedder, AbstractEmbedder
using PromptingTools: MODEL_EMBEDDING

@kwdef struct OpenAIBatchEmbedder <: AbstractEasyEmbedder
    embedder::BatchEmbedder=BatchEmbedder()
    model::String=MODEL_EMBEDDING
end

# Delegate the get_embeddings method to the internal BatchEmbedder
function get_embeddings(embedder::OpenAIBatchEmbedder, docs::AbstractVector{<:AbstractString}; kwargs...)
    get_embeddings(embedder.embedder, docs; model=embedder.model, kwargs...)
end

get_model_name(embedder::OpenAIBatchEmbedder) = embedder.model

# Add this at the end of the file
function create_openai_embedder(;
    model::String = "text-embedding-3-small",
    top_k::Int = 300,
    cache_prefix="",
)
    embedder = CachedBatchEmbedder(; embedder=OpenAIBatchEmbedder(; model=model), cache_prefix)
    EmbeddingIndexBuilder(embedder=embedder, top_k=top_k)
end

export create_openai_embedder

