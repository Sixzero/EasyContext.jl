
using HTTP
using JSON3
using PromptingTools
using RAGTools: get_embeddings
using ProgressMeter

"""
    JinaEmbedder <: AbstractEasyEmbedder

A struct for embedding documents using Jina AI's embedding models.

Supports two model options:
1. "jina-embeddings-v3": A general-purpose embedding model.
2. "jina-colbert-v2": A ColBERT-based embedding model for dense retrieval tasks.
1. "jina-embeddings-v2-base-code" (default): A general-purpose embedding model.

# Fields
- `api_url::String`: The API endpoint URL.
- `api_key::String`: The API key for authentication.
- `model::String`: The name of the embedding model to use.
- `dimensions::Union{Int, Nothing}`: The number of dimensions for the embedding (required for ColBERT model).
- `input_type::String`: The type of input (e.g., "document" or "query", required for ColBERT model).
- `rate_limiter::RateLimiterRPM`: A rate limiter to manage API request rates.
- `http_post::Function`: The function to use for HTTP POST requests.
"""
@kwdef mutable struct JinaEmbedder <: AbstractEasyEmbedder
    api_url::String = "https://api.jina.ai/v1/embeddings"
    api_key::String = get(ENV, "JINA_API_KEY", "")
    model::String = "jina-embeddings-v2-base-code"
    dimensions::Union{Int, Nothing} = nothing
    input_type::String = "document"
    rate_limiter::RateLimiterRPM = RateLimiterRPM()
    http_post::Function = HTTP.post
    verbose::Bool = true
end

function process_batch(batch, embedder::JinaEmbedder)
    payload = Dict(
        "model" => embedder.model,
        "normalized" => true,
        "embedding_type" => "float",
        "input" => batch
    )
    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)"
    ]

    if embedder.model == "jina-colbert-v2"
        embedder.api_url = "https://api.jina.ai/v1/multi-vector"
        payload["dimensions"] = embedder.dimensions
        payload["input_type"] = embedder.input_type
    end

    response = embedder.http_post(embedder.api_url, headers, JSON3.write(payload))

    if response.status == 200
        result = JSON3.read(String(response.body))
        return [e["embedding"] for e in result["data"]]
    else
        error("Failed to get embeddings for batch. Status code: $(response.status)")
    end
end

function get_embeddings(embedder::JinaEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    process_batch_limited = with_rate_limiter(process_batch, embedder.rate_limiter)

    batch_size = 1024 # 2048 is the max, but it caused error (maybe for really large requests)
    batches = [docs[i:min(i + batch_size - 1, end)] for i in 1:batch_size:length(docs)]
    if length(batches) == 1
        embeddings = process_batch_limited(batches[1], embedder)
        all_embeddings = stack(embeddings, dims=2)
    else
        progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
        embeddings = asyncmap(batches, ntasks=4) do batch
            result = process_batch_limited(batch, embedder)
            result = stack(result, dims=2)
            next!(progress)
            return result
        end
        all_embeddings = reduce(hcat, embeddings)
    end

    if verbose
        @info "Embedding complete for $(length(docs)) documents using $(embedder.model)."
    end

    return all_embeddings
end

# Add this at the end of the file
function create_jina_embedder(;
    model::String = "jina-embeddings-v2-base-code",
    dimensions::Union{Int, Nothing} = nothing,
    input_type::String = "document",
    cache_prefix="",
)
    jina_embedder = JinaEmbedder(; model=model, dimensions=dimensions, input_type=input_type)
    embedder = CachedBatchEmbedder(;embedder=jina_embedder, cache_prefix)
end

export create_jina_embedder

# Update humanize method
humanize(e::JinaEmbedder) = "Jina:$(e.model)"

