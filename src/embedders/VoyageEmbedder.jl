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
- `input_type::Union{String, Nothing}`: The type of input (e.g., "document" or "query").
- `rate_limiter::RateLimiterTPM`: A rate limiter to manage API request rates.
- `http_post::Function`: The HTTP post function to use for making requests.
"""
@kwdef mutable struct VoyageEmbedder <: AbstractEasyEmbedder
    api_url::String = "https://api.voyageai.com/v1/embeddings"
    api_key::String = get(ENV, "VOYAGE_API_KEY", "")
    model::String = "voyage-code-2"
    input_type::Union{String, Nothing} = nothing
    rate_limiter::RateLimiterTPM = RateLimiterTPM()
    http_post::Function = HTTP.post
    verbose::Bool = true
end

function get_embeddings(embedder::VoyageEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)"
    ]

    function process_batch(batch)
        payload = Dict(
            "model" => embedder.model,
            "input" => batch,
            "truncation" => false
        )
        
        if !isnothing(embedder.input_type)
            payload["input_type"] = embedder.input_type
        end

        response = retry_on_rate_limit(max_retries=5, verbose=verbose) do
            embedder.http_post(embedder.api_url, headers, JSON3.write(payload))
        end

        if response.status != 200
            error("Failed to get embeddings for batch. Status code: $(response.status)")
        end
        result = JSON3.read(String(response.body))
        return [e["embedding"] for e in result["data"]], result["usage"]["total_tokens"]
    end

    process_batch_limited = with_rate_limiter_tpm(process_batch, embedder.rate_limiter)

    # Token and batch size limits
    max_tokens_per_batch = 120_000
    max_batch_size = 128
    
    # Create batches based on both token count and size limit
    current_batch = String[]
    current_tokens = 0
    batches = Vector{String}[]

    for doc in docs
        doc_tokens = estimate_tokens(doc, CharCountDivTwo)
        if current_tokens + doc_tokens > max_tokens_per_batch || length(current_batch) >= max_batch_size
            push!(batches, current_batch)
            current_batch = String[doc]
            current_tokens = doc_tokens
        else
            push!(current_batch, doc)
            current_tokens += doc_tokens
        end
    end
    !isempty(current_batch) && push!(batches, current_batch)

    progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
    results = asyncmap(batches, ntasks=20) do batch
        embeddings, tokens = process_batch_limited(batch)
        embeddings_matrix = stack(embeddings, dims=2)
        verbose && @info "Batch processed. Size: $(size(embeddings_matrix)), Tokens: $tokens"
        next!(progress)

        return embeddings_matrix, tokens
    end

    all_embeddings = reduce(hcat, first.(results))
    total_tokens = sum(last.(results))

    if verbose
        @info "Embedding complete for $(length(docs)) documents using $(embedder.model). Total tokens: $total_tokens"
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

    time = @elapsed embeddings, total_tokens = get_embeddings(embedder, docs; verbose=verbose, kwargs...)

    content = mapreduce(postprocess, hcat, eachcol(embeddings))

    msg = PromptingTools.DataMessage(;
        content = content,
        status = 200,
        cost = 0.0,  # Voyage AI doesn't provide cost information
        tokens = (total_tokens, 0),
        elapsed = time
    )

    return msg
end

# Add this at the end of the file
function create_voyage_embedder(;
    model::String = "voyage-code-2", # or voyage-3
    top_k::Int = 300,
    input_type::Union{String, Nothing} = nothing,
    verbose::Bool = true,
    cache_prefix=""
)
    voyage_embedder = VoyageEmbedder(; model, input_type, verbose)
    embedder = CachedBatchEmbedder(;embedder=voyage_embedder, cache_prefix, verbose)
    EmbeddingIndexBuilder(embedder=embedder, top_k=top_k)
end

export create_voyage_embedder

