using HTTP
using JSON3
using PromptingTools
using RAGTools: get_embeddings
using ProgressMeter
using LLMRateLimiters
using LLMRateLimiters: retry_on_rate_limit
# Pricing constants (USD per million units)
const COHERE_PRICING = Dict(
    "embed-v4.0" => Dict(
        "input_tokens" => 0.12 / 1_000_000,  # $0.12 per million text tokens
        "images" => 0.47 / 1_000_000         # $0.47 per million image tokens
    ),
    # Add other models as needed with their pricing
    "default" => Dict(
        "input_tokens" => 0.12 / 1_000_000,  # Default text token price
        "images" => 0.47 / 1_000_000         # Default image token price
    )
)

"""
    calculate_cohere_cost(model::String, billed_units::Dict)

Calculate the cost based on the model and billed units.
"""
function calculate_cohere_cost(model::String, billed_units::Dict)
    # Get pricing for the model or use default pricing
    pricing = get(COHERE_PRICING, model, COHERE_PRICING["default"])
    
    # Calculate cost based on billed units
    cost = 0.0
    for (unit_type, count) in billed_units
        if haskey(pricing, unit_type)
            cost += count * pricing[unit_type]
        end
    end
    
    return cost
end

"""
    CohereEmbedder <: AbstractEasyEmbedder

A struct for embedding documents using Cohere's embedding models.

# Fields
- `api_url::String`: The API endpoint URL.
- `api_key::String`: The API key for authentication.
- `model::String`: The name of the embedding model to use.
- `input_type::String`: The type of input (e.g., "search_document", "search_query", "classification", "clustering", "image").
- `truncate::String`: Truncation strategy ("NONE", "START", "END").
- `embedding_types::Vector{String}`: Types of embeddings to return (e.g., "float", "int8", "uint8", "binary", "ubinary").
- `rate_limiter::RateLimiterRPM`: A rate limiter to manage API request rates.
- `http_post::Function`: The function to use for HTTP POST requests.
- `verbose::Bool`: Whether to print verbose output.
"""
@kwdef mutable struct CohereEmbedder <: AbstractEasyEmbedder
    api_url::String = "https://api.cohere.com/v2/embed"
    api_key::String = get(ENV, "COHERE_API_KEY", "")
    model::String = "embed-multilingual-v3.0"
    rate_limiter::RateLimiterRPM = RateLimiterRPM(max_requests=300, time_window=60.0)  # 300 requests per minute
    http_post::Function = HTTP.post
    verbose::Bool = true
end

function get_embeddings_document(embedder::CohereEmbedder, docs::AbstractVector{<:AbstractString};
kwargs...)
    get_embeddings(embedder, docs; input_type="search_document", kwargs...)
end
function get_embeddings_query(embedder::CohereEmbedder, docs::AbstractVector{<:AbstractString};
    kwargs...)
    get_embeddings(embedder, docs; input_type="search_query", kwargs...)
end
function get_embeddings_image(embedder::CohereEmbedder, docs::AbstractVector{<:AbstractString};
    images::Vector{<:AbstractString}, kwargs...)
    get_embeddings(embedder, docs; input_type="image", images, kwargs...)
end

function get_embeddings(embedder::CohereEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    input_type::String = "search_document", # for the query use: "search_query"
    images::AbstractVector{<:AbstractString} = String[],
    cost_tracker = Threads.Atomic{Float64}(0.0),
    ntasks::Int = 20,
    truncate::String = "NONE",
    embedding_types::Vector{String} = ["float"],
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)",
        "Accept" => "application/json"
    ]

    function process_batch(batch, batch_images=[])
        payload = Dict(
            "model" => embedder.model,
            "input_type" => input_type,
            "truncate" => truncate,
            "embedding_types" => embedding_types
        )
        
        # Add texts if provided
        if !isempty(batch)
            payload["texts"] = batch
        end
        
        # Add images if provided
        if !isempty(batch_images)
            payload["images"] = batch_images
        end

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
            embeddings = if "float" in embedding_types
                result.embeddings.float
            elseif "int8" in embedding_types
                result.embeddings.int8
            elseif "uint8" in embedding_types
                result.embeddings.uint8
            elseif "binary" in embedding_types
                result.embeddings.binary
            elseif "ubinary" in embedding_types
                result.embeddings.ubinary
            else
                result.embeddings.float  # Default fallback
            end
            
            # Extract billed units from the response
            billed_units = Dict{String, Int}()
            
            if haskey(result, :meta) && haskey(result.meta, :billed_units)
                for (key, value) in pairs(result.meta.billed_units)
                    billed_units[String(key)] = value
                end
            end
            
            # If no billed units were reported, estimate
            if isempty(billed_units)
                # Rough estimate: 1 token ≈ 4 characters
                if !isempty(batch)
                    billed_units["input_tokens"] = sum(length.(batch)) ÷ 4
                end
                if !isempty(batch_images)
                    billed_units["images"] = length(batch_images)
                end
            
            end
            
            # Calculate cost based on billed units
            cost = calculate_cohere_cost(embedder.model, billed_units)
            Threads.atomic_add!(cost_tracker, cost)
            
            return embeddings, billed_units
        catch e
            @error "Request failed" payload=payload exception=(e, catch_backtrace())
            rethrow(e)
        end
    end

    process_batch_limited = with_rate_limiter(process_batch, embedder.rate_limiter)

    # Handle image embeddings
    if input_type == "image"
        if isempty(images)
            error("No images provided for image embedding")
        end
        
        if verbose
            @info "Processing $(length(images)) images"
        end
        
        # Process images in batches of 1 as per API limitation
        
        emb, _ = process_batch_limited(String[], images)

        # Properly handle image embeddings - stack them as columns in a matrix
        all_embeddings = stack(emb, dims=2)
        
        if verbose
            @info "Embedding complete for $(length(images)) images using $(embedder.model)."
        end
        
        return all_embeddings
    end

    # Handle text embeddings
    # Calculate optimal batch size based on document count and desired number of tasks
    # Cohere supports up to 96 texts per request
    max_batch_size = 96
    
    # Calculate batch size to create at least ntasks batches, but not exceeding max_batch_size
    total_docs = length(docs)
    optimal_batch_size = min(max_batch_size, max(1, total_docs ÷ ntasks))
    
    # Create batches with the calculated optimal size
    batches = [docs[i:min(i + optimal_batch_size - 1, end)] for i in 1:optimal_batch_size:total_docs]
    
    if verbose
        @info "Processing $(length(docs)) documents in $(length(batches)) batches (batch size: $optimal_batch_size). Cost: $(cost_tracker[])\$"
    end
    
    if length(batches) == 1
        embeddings, _ = process_batch_limited(batches[1])
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
    end

    if verbose
        @info "Embedding complete for $(length(docs)) documents using $(embedder.model). Cost: $(cost_tracker[])\$"
    end

    return all_embeddings
end

# Add this at the end of the file
function create_cohere_embedder(;
    model::String = "embed-v4.0",
    input_type::String = "classification",
    verbose::Bool = true,
    cache_prefix="",
)
    cohere_embedder = CohereEmbedder(; model, verbose)
    embedder = CachedBatchEmbedder(; embedder=cohere_embedder, cache_prefix, verbose)
end

# Update humanize method
humanize(e::CohereEmbedder) = "Cohere:$(e.model)"

export create_cohere_embedder
