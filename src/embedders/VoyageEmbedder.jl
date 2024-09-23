using HTTP
using JSON3
using PromptingTools
using PromptingTools.Experimental.RAGTools: get_embeddings
using ProgressMeter

"""
    VoyageEmbedder <: AbstractEasyEmbedder

A struct for embedding documents using Voyage AI's embedding models.

# Fields
- `api_url::String`: The API endpoint URL.
- `api_key::String`: The API key for authentication.
- `model::String`: The name of the embedding model to use.
- `input_type::String`: The type of input (e.g., "document" or "query").
- `rate_limiter::RateLimiter`: A rate limiter to manage API request rates.
"""
@kwdef mutable struct VoyageEmbedder <: AbstractEasyEmbedder
    api_url::String = "https://api.voyageai.com/v1/embeddings"
    api_key::String = get(ENV, "VOYAGE_API_KEY", "")
    model::String = "voyage-code-2" # or voyage-3
    input_type::String = "document"
    rate_limiter::RateLimiter = RateLimiter()
end

function get_embeddings(embedder::VoyageEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = true,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)"
    ]

    function process_batch(batch)
        payload = Dict(
            "model" => embedder.model,
            "input_type" => embedder.input_type,
            "input" => batch
        )

        response = HTTP.post(embedder.api_url, headers, JSON3.write(payload))

        if response.status == 200
            result = JSON3.read(String(response.body))
            return [e["embedding"] for e in result["data"]]
        else
            error("Failed to get embeddings for batch. Status code: $(response.status)")
        end
    end

    process_batch_limited = with_rate_limiter(process_batch, embedder.rate_limiter)

    batch_size = 128 # Voyage AI's max batch size
    batches = [docs[i:min(i + batch_size - 1, end)] for i in 1:batch_size:length(docs)]

    progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
    embeddings = asyncmap(batches, ntasks=4) do batch
        result = process_batch_limited(batch)
        result = stack(result, dims=2)
        next!(progress)
        return result
    end
    all_embeddings = reduce(hcat, embeddings)

    if verbose
        @info "Embedding complete for $(length(docs)) documents using $(embedder.model)."
    end

    return all_embeddings
end

# Extend aiembed for VoyageEmbedder
function PromptingTools.aiembed(embedder::VoyageEmbedder,
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
        cost = 0.0,  # Voyage AI doesn't provide cost information
        tokens = (0, 0),  # Voyage AI doesn't provide token count
        elapsed = time
    )

    verbose && @info PromptingTools._report_stats(msg, embedder.model)

    return msg
end

# Helper function to create a VoyageEmbedder instance
function create_voyage_embedder(;
    api_url::String = "https://api.voyageai.com/v1/embeddings",
    api_key::String = get(ENV, "VOYAGE_API_KEY", ""),
    model::String = "voyage-code-2",
    input_type::String = "document"
)
    VoyageEmbedder(; api_url, api_key, model, input_type)
end

# Add this at the end of the file
function create_voyage_embedder(;
    model::String = "voyage-code-2",
    top_k::Int = 300,
    input_type::String = "document"
)
    voyage_embedder = VoyageEmbedder(; model=model, input_type=input_type)
    embedder = CachedBatchEmbedder(;embedder=voyage_embedder)
    EmbeddingIndexBuilder(embedder=embedder, top_k=top_k)
end

export create_voyage_embedder

