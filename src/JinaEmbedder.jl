using HTTP
using JSON3
using PromptingTools
using PromptingTools.Experimental.RAGTools: AbstractEmbedder, get_embeddings

"""
    JinaEmbedder <: AbstractEmbedder

A struct for embedding documents using Jina AI's embedding models.

Supports two model options:
1. "jina-embeddings-v2-base-code" (default): A general-purpose embedding model.
2. "jina-colbert-v2": A ColBERT-based embedding model for dense retrieval tasks.

# Fields
- `api_url::String`: The API endpoint URL.
- `api_key::String`: The API key for authentication.
- `model::String`: The name of the embedding model to use.
- `dimensions::Union{Int, Nothing}`: The number of dimensions for the embedding (required for ColBERT model).
- `input_type::String`: The type of input (e.g., "document" or "query", required for ColBERT model).
"""
@kwdef mutable struct JinaEmbedder <: AbstractEmbedder
    api_url::String = "https://api.jina.ai/v1/embeddings"
    api_key::String = get(ENV, "JINA_API_KEY", "")
    model::String = "jina-embeddings-v2-base-code"
    dimensions::Union{Int, Nothing} = nothing
    input_type::String = "document"
end

function get_embeddings(embedder::JinaEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = true,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)"
    ]

    payload = Dict(
        "model" => embedder.model,
        "normalized" => true,
        "embedding_type" => "float",
        "input" => docs
    )

    if embedder.model == "jina-colbert-v2"
        embedder.api_url = "https://api.jina.ai/v1/multi-vector"
        payload["dimensions"] = embedder.dimensions
        payload["input_type"] = embedder.input_type
    end

    response = HTTP.post(embedder.api_url, headers, JSON3.write(payload))

    if response.status == 200
        result = JSON3.read(String(response.body))
        embeddings = [e["embedding"] for e in result["data"]]
        
        if verbose
            @info "Embedding complete for $(length(docs)) documents using $(embedder.model)."
        end

        return embeddings
    else
        error("Failed to get embeddings. Status code: $(response.status)")
    end
end

# Extend aiembed for JinaEmbedder
function PromptingTools.aiembed(embedder::JinaEmbedder,
    doc_or_docs::Union{AbstractString, AbstractVector{<:AbstractString}},
    postprocess::F = identity;
    verbose::Bool = true,
    kwargs...) where {F <: Function}

    docs = doc_or_docs isa AbstractString ? [doc_or_docs] : doc_or_docs

    time = @elapsed embeddings = get_embeddings(embedder, docs; verbose=verbose, kwargs...)

    content = mapreduce(postprocess, hcat, embeddings)

    msg = PromptingTools.DataMessage(;
        content = content,
        status = 200,
        cost = 0.0,  # Jina doesn't provide cost information
        tokens = (0, 0),  # Jina doesn't provide token count
        elapsed = time
    )

    verbose && @info PromptingTools._report_stats(msg, embedder.model)

    return msg
end

# Helper function to create a JinaEmbedder instance
function create_jina_embedder(;
    api_url::String = "https://api.jina.ai/v1/embeddings",
    api_key::String = get(ENV, "JINA_API_KEY", ""),
    model::String = "jina-embeddings-v2-base-code",
    dimensions::Union{Int, Nothing} = nothing,
    input_type::String = "document"
)
    JinaEmbedder(; api_url, api_key, model, dimensions, input_type)
end

