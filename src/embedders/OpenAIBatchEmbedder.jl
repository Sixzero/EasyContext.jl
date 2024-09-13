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
