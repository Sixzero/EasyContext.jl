using HTTP
using JSON3
using PromptingTools
using PromptingTools.Experimental.RAGTools: get_embeddings
using ProgressMeter
using LLMRateLimiters
using LLMRateLimiters: retry_on_rate_limit

"""
    CohereEmbedder <: AbstractEasyEmbedder

A struct for embedding documents using Cohere's embedding models.

# Fields
- `api_url::String`: The API endpoint URL.
- `api_key::String`: The API key for authentication.
- `model::String`: The name of the embedding model to use.
- `input_type::String`: The type of input (e.g., "search_document", "search_query", "classification", "clustering").
- `truncate::String`: Truncation strategy ("NONE", "START", "END").
- `embedding_types::Vector{String}`: Types of embeddings to return (e.g., "float", "int8", "uint8", "binary", "ubinary").
- `rate_limiter::RateLimiterRPM`: A rate limiter to manage API request rates.
- `http_post::Function`: The function to use for HTTP POST requests.
- `verbose::Bool`: Whether to print verbose output.
"""
@kwdef mutable struct CohereEmbedder <: AbstractEasyEmbedder
    api_url::String = "https://api.cohere.ai/v1/embed"
    api_key::String = get(ENV, "COHERE_API_KEY", "")
    model::String = "embed-multilingual-v3.0"
    truncate::String = "END"
    embedding_types::Vector{String} = ["float"]
    rate_limiter::RateLimiterRPM = RateLimiterRPM(max_requests=300, time_window=60.0)  # 300 requests per minute
    http_post::Function = HTTP.post
    verbose::Bool = true
end

function get_embeddings(embedder::CohereEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    input_type::String = "search_document", # for the query use: "search_query"
    cost_tracker = Threads.Atomic{Float64}(0.0),
    ntasks::Int = 20,
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)",
        "Accept" => "application/json"
    ]

    function process_batch(batch)
        payload = Dict(
            "model" => embedder.model,
            "texts" => batch,
            "input_type" => input_type,
            "truncate" => embedder.truncate,
            "embedding_types" => embedder.embedding_types
        )

        try
            response = retry_on_rate_limit(max_retries=5, verbose=verbose) do
                embedder.http_post(embedder.api_url, headers, JSON3.write(payload))
            end

            if response.status != 200
                @error "Failed request payload" payload
                error("Failed to get embeddings for batch. Status code: $(response.status), Response: $(String(response.body))")
            end
            
            result = JSON3.read(String(response.body))
            
            # Extract embeddings based on the requested type (default to float)
            embeddings = if "float" in embedder.embedding_types
                result.embeddings.float
            elseif "int8" in embedder.embedding_types
                result.embeddings.int8
            elseif "uint8" in embedder.embedding_types
                result.embeddings.uint8
            elseif "binary" in embedder.embedding_types
                result.embeddings.binary
            elseif "ubinary" in embedder.embedding_types
                result.embeddings.ubinary
            else
                result.embeddings.float  # Default fallback
            end
            
            # Calculate approximate token usage (Cohere doesn't return token counts)
            # Rough estimate: 1 token ≈ 4 characters
            approx_tokens = sum(length.(batch)) ÷ 4
            
            # Estimate cost (adjust based on Cohere's pricing)
            # As of my knowledge, Cohere charges around $0.10 per 1000 requests
            # This is a very rough estimate
            cost = 0.0001 * length(batch)
            Threads.atomic_add!(cost_tracker, cost)
            
            return embeddings, approx_tokens
        catch e
            @error "Request failed" payload=payload exception=(e, catch_backtrace())
            rethrow(e)
        end
    end

    process_batch_limited = with_rate_limiter(process_batch, embedder.rate_limiter)

    # Calculate optimal batch size based on document count and desired number of tasks
    # Cohere supports up to 96 texts per request
    max_batch_size = 96
    
    # Calculate batch size to create at least ntasks batches, but not exceeding max_batch_size
    total_docs = length(docs)
    optimal_batch_size = min(max_batch_size, max(1, total_docs ÷ ntasks))
    
    # Create batches with the calculated optimal size
    batches = [docs[i:min(i + optimal_batch_size - 1, end)] for i in 1:optimal_batch_size:total_docs]
    
    if verbose
        @info "Processing $(length(docs)) documents in $(length(batches)) batches (batch size: $optimal_batch_size)"
    end
    
    if length(batches) == 1
        embeddings, tokens = process_batch_limited(batches[1])
        all_embeddings = stack(embeddings, dims=2)
    else
        show_progress = length(batches) > ntasks
        progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
        
        # Use the specified number of tasks for asyncmap
        results = asyncmap(batches, ntasks=ntasks) do batch
            result = process_batch_limited(batch)
            show_progress && verbose && next!(progress)
            return result
        end
        
        embeddings = [emb for (emb, _) in results]
        all_embeddings = reduce(hcat, [stack(emb, dims=2) for emb in embeddings])
        tokens = sum(last.(results))
    end

    if verbose
        @info "Embedding complete for $(length(docs)) documents using $(embedder.model). Approx tokens: $tokens"
    end

    return all_embeddings
end

# Add this at the end of the file
function create_cohere_embedder(;
    model::String = "embed-multilingual-v3.0",
    embedding_types::Vector{String} = ["float"],
    verbose::Bool = true,
    cache_prefix="",
)
    cohere_embedder = CohereEmbedder(; model, embedding_types, verbose)
    embedder = CachedBatchEmbedder(; embedder=cohere_embedder, cache_prefix, verbose)
end

# Update humanize method
humanize(e::CohereEmbedder) = "Cohere:$(e.model)"

export create_cohere_embedder
