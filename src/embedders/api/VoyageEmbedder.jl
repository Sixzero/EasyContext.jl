using HTTP
using JSON3
using PromptingTools
using RAGTools: get_embeddings
using ProgressMeter
using LLMRateLimiters
using LLMRateLimiters: retry_on_rate_limit


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
    rate_limiter::RateLimiterTPM = RateLimiterTPM(max_tokens=3_000_000)
    http_post::Function = HTTP.post
    verbose::Bool = true
end
function get_embeddings_document(embedder::VoyageEmbedder, docs::AbstractVector{<:AbstractString};
kwargs...)
    get_embeddings(embedder, docs; input_type="document", kwargs...)
end
function get_embeddings_query(embedder::VoyageEmbedder, docs::AbstractVector{<:AbstractString};
    kwargs...)
    get_embeddings(embedder, docs; input_type="query", kwargs...)
end
function get_embeddings(embedder::VoyageEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    input_type::Union{String, Nothing} = nothing,
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
        
        if !isnothing(input_type)
            payload["input_type"] = input_type
        end

        try
            response = retry_on_rate_limit(max_retries=5, verbose=verbose) do
                embedder.http_post(embedder.api_url, headers, JSON3.write(payload))
            end

            if response.status != 200
                @error "Failed request payload" payload
                error("Failed to get embeddings for batch. Status code: $(response.status)")
            end
            result = JSON3.read(String(response.body))
            return [e["embedding"] for e in result["data"]], result["usage"]["total_tokens"]
        catch e
            @error "Request failed" payload=payload exception=(e, catch_backtrace())
            rethrow(e)
        end
    end

    process_batch_limited = with_rate_limiter_tpm(process_batch, embedder.rate_limiter)

    # ... existing headers and process_batch setup ...

    # Create batches
    batches = create_batches(docs, max_tokens_per_batch=100_000, max_batch_size=128)
    
    # Process batches with error tracking
    progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
    results = process_batches_with_partial_results(
        batches, 
        batch -> process_batch_limited(batch),
        progress;
        ntasks=8,
        verbose
    )
    
    # Return results or throw partial results
    return collect_results(results, length(docs), embedder.model, verbose)
end

function create_batches(docs; max_tokens_per_batch=100_000, max_batch_size=128)
    batches = Vector{String}[]
    current_batch = String[]
    current_tokens = 0
    
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
    return batches
end

function process_batches_with_partial_results(batches, process_fn, progress; ntasks=8, verbose=true)
    successful_results = Dict{Int, Tuple{Matrix{Float32}, Int}}()
    batch_sizes = length.(batches)
    cumulative_indices = cumsum(batch_sizes)
    
    try
        asyncmap(enumerate(batches), ntasks=ntasks) do (batch_idx, batch)
            try
                embeddings, tokens = process_fn(batch)
                embeddings_matrix = stack(embeddings, dims=2)
                successful_results[batch_idx] = (embeddings_matrix, tokens)
                verbose && (length(batches) > 1) && @info "Batch processed. Size: $(size(embeddings_matrix)), Tokens: $tokens"
                next!(progress)
            catch e
                @error "Batch $batch_idx failed" exception=e
                rethrow(e)
            end
        end
    catch e
        if !isempty(successful_results)
            return create_partial_results(successful_results, batch_sizes, cumulative_indices, e)
        end
        rethrow(e)
    end
    return successful_results
end

function create_partial_results(successful_results, batch_sizes, cumulative_indices, error)
    # Calculate failed indices
    failed_batch_indices = setdiff(1:length(batch_sizes), keys(successful_results))
    failed_indices = reduce(vcat, 
        [((i == 1 ? 1 : cumulative_indices[i-1] + 1):cumulative_indices[i]) 
         for i in failed_batch_indices], 
        init=Int[])
    
    # Convert successful batch results
    successful_embeddings = Dict{Int, Vector{Float32}}()
    for batch_idx in sort!(collect(keys(successful_results)))
        emb_matrix, _ = successful_results[batch_idx]
        start_idx = batch_idx == 1 ? 1 : cumulative_indices[batch_idx-1] + 1
        for (j, emb) in enumerate(eachcol(emb_matrix))
            successful_embeddings[start_idx + j - 1] = emb
        end
    end
    
    throw(PartialEmbeddingResults(successful_embeddings, failed_indices, error))
end

function collect_results(results::Dict, total_docs, model, verbose)
    all_embeddings = reduce(hcat, first.(values(results)))
    total_tokens = sum(last.(values(results)))
    
    verbose && @info "Embedding complete for $total_docs documents using $model. Total tokens: $total_tokens"
    
    return all_embeddings
end

# Add this at the end of the file
function create_voyage_embedder(;
    model::String = "voyage-code-3", # or voyage-3
    verbose::Bool = true,
    cache_prefix=""
)
    voyage_embedder = VoyageEmbedder(; model, verbose)
    embedder = CachedBatchEmbedder(;embedder=voyage_embedder, cache_prefix, verbose)
end

# Update humanize method
humanize(e::VoyageEmbedder) = "Voyage:$(e.model)"

export create_voyage_embedder

