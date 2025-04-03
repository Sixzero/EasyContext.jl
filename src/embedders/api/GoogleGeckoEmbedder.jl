using HTTP
using JSON3
using PromptingTools
using PromptingTools.Experimental.RAGTools: get_embeddings
using ProgressMeter
using LLMRateLimiters
using LLMRateLimiters: retry_on_rate_limit
using Dates

# Module-level cache for authentication tokens
const AUTH_TOKEN_CACHE = Dict{String, Tuple{String, DateTime}}()
const PROJECT_ID_CACHE = Ref{String}("")

"""
    GoogleGeckoEmbedder <: AbstractEasyEmbedder

A struct for embedding documents using Google's Gecko embedding models.

# Fields
- `project_id::String`: The Google Cloud project ID.
- `location::String`: The Google Cloud region (e.g., "us-central1").
- `model::String`: The name of the embedding model to use.
- `task_type::String`: The type of task (e.g., "RETRIEVAL_DOCUMENT", "RETRIEVAL_QUERY", "SEMANTIC_SIMILARITY").
- `auto_truncate::Bool`: Whether to automatically truncate text that exceeds token limits.
- `output_dimensionality::Union{Int, Nothing}`: Optional dimensionality for output embeddings.
- `rate_limiter::RateLimiterRPM`: A rate limiter to manage API request rates.
- `http_post::Function`: The function to use for HTTP POST requests.
- `verbose::Bool`: Whether to print verbose output.
- `api_key::String`: The API key for authentication.
"""
@kwdef mutable struct GoogleGeckoEmbedder <: AbstractEasyEmbedder
    project_id::String = get_project_id()
    location::String = "us-central1"
    model::String = "text-embedding-005"
    task_type::String = "RETRIEVAL_DOCUMENT"
    auto_truncate::Bool = false
    output_dimensionality::Union{Int, Nothing} = nothing
    rate_limiter::RateLimiterRPM = RateLimiterRPM(max_requests=1000, time_window=60.0)  # 100 requests per minute
    http_post::Function = HTTP.post
    verbose::Bool = true
    api_key::String = get(ENV, "VERTEX_AI_API_KEY", "")
end

# Get project ID from environment or gcloud
function get_project_id()
    # Check if we already have a cached project ID
    if !isempty(PROJECT_ID_CACHE[])
        return PROJECT_ID_CACHE[]
    end
    
    # Try to get from environment variable
    project_id = get(ENV, "GOOGLE_CLOUD_PROJECT", "")
    
    # If not found, try to get from gcloud
    if isempty(project_id)
        try
            project_id = String(strip(read(`gcloud config get-value project`, String)))
            if isempty(project_id) || project_id == "(unset)"
                error("Google Cloud project ID is not set. Please set GOOGLE_CLOUD_PROJECT environment variable or configure it with 'gcloud config set project YOUR_PROJECT_ID'")
            end
        catch e
            error("Failed to get Google Cloud project ID: $e. Please set GOOGLE_CLOUD_PROJECT environment variable or configure it with 'gcloud config set project YOUR_PROJECT_ID'")
        end
    end
    
    # Cache the project ID
    PROJECT_ID_CACHE[] = project_id
    
    return project_id
end

# Get authentication token from module-level cache or fetch a new one
function get_auth_token(embedder::GoogleGeckoEmbedder; force_refresh::Bool=false)
    # Create a cache key based on project and location
    cache_key = "$(embedder.project_id):$(embedder.location)"
    
    # Check if we have a valid cached token and not forcing refresh
    current_time = now()
    if !force_refresh && haskey(AUTH_TOKEN_CACHE, cache_key)
        token, expiry = AUTH_TOKEN_CACHE[cache_key]
        if current_time < expiry
            return token
        end
    end
    
    # Get a new token from gcloud
    token = try
        # Use regular user token first (this worked in curl)
        String(strip(read(`gcloud auth print-access-token`, String)))
    catch e
        error("Failed to get authentication token. Tried both regular and application-default tokens. Error: $e. Make sure you're authenticated with gcloud.")
    end
    
    # Verify token is not empty
    if isempty(token)
        error("Authentication token is empty. Please ensure you're properly authenticated with Google Cloud.")
    end
    
    # Cache the token with a 50-minute expiry (tokens typically last 60 minutes)
    AUTH_TOKEN_CACHE[cache_key] = (token, current_time + Minute(50))
    
    return token
end

function get_embeddings(embedder::GoogleGeckoEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = embedder.verbose,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    ntasks::Int = 20,
    kwargs...)

    # Construct the API URL
    api_url = "https://$(embedder.location)-aiplatform.googleapis.com/v1/projects/$(embedder.project_id)/locations/$(embedder.location)/publishers/google/models"
    
    # Construct the full API URL with the model
    full_api_url = "$(api_url)/$(embedder.model):predict"
    
    # Get authentication token (cached if possible)
    auth_token = get_auth_token(embedder)
    
    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(auth_token)"
    ]

    function process_batch(batch)
        # Prepare instances for the API request
        instances = [Dict("content" => text, "task_type" => embedder.task_type) for text in batch]
        
        # Prepare parameters
        parameters = Dict("autoTruncate" => embedder.auto_truncate)
        if embedder.output_dimensionality !== nothing
            parameters["outputDimensionality"] = embedder.output_dimensionality
        end
        
        payload = Dict(
            "instances" => instances,
            "parameters" => parameters
        )

        try
            response = retry_on_rate_limit(max_retries=5, verbose=verbose) do
                embedder.http_post(full_api_url, headers, JSON3.write(payload))
            end

            if response.status != 200
                # If we get a 401 Unauthorized, try refreshing the token once
                if response.status == 401
                    if verbose
                        @info "Authentication failed. Refreshing token and retrying..."
                    end
                    # Force refresh the token
                    auth_token = get_auth_token(embedder, force_refresh=true)
                    headers = [
                        "Content-Type" => "application/json",
                        "Authorization" => "Bearer $(auth_token)"
                    ]
                    
                    # Retry with new token
                    response = embedder.http_post(full_api_url, headers, JSON3.write(payload))
                    
                    # If still not 200, then error
                    if response.status != 200
                        @error "Failed request payload after token refresh" payload
                        error("Failed to get embeddings for batch after token refresh. Status code: $(response.status), Response: $(String(response.body))")
                    end
                else
                    @error "Failed request payload" payload
                    error("Failed to get embeddings for batch. Status code: $(response.status), Response: $(String(response.body))")
                end
            end
            
            result = JSON3.read(String(response.body))
            
            # Extract embeddings from the response
            embeddings = []
            token_count = 0
            
            for prediction in result.predictions
                # Extract embedding values
                values = prediction.embeddings.values
                push!(embeddings, values)
                
                # Extract token count if available
                if haskey(prediction.embeddings.statistics, :token_count)
                    token_count += prediction.embeddings.statistics.token_count
                end
            end
            
            # Estimate cost (adjust based on Google's pricing)
            # As of my knowledge, Google charges around $0.0001 per 1000 characters
            # This is a very rough estimate
            approx_chars = sum(length.(batch))
            cost = 0.0001 * (approx_chars / 1000)
            Threads.atomic_add!(cost_tracker, cost)
            
            return embeddings, token_count
        catch e
            @error "Request failed" payload=payload exception=(e, catch_backtrace())
            rethrow(e)
        end
    end

    process_batch_limited = with_rate_limiter(process_batch, embedder.rate_limiter)

    # Calculate optimal batch size based on document count and desired number of tasks
    # Google supports up to 5 texts per request in most regions
    max_batch_size = embedder.model === "text-embedding-large-exp-03-07" ? 1 : 5
    
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
        progress = Progress(length(batches), desc="Processing batches: ", showspeed=true)
        
        # Use the specified number of tasks for asyncmap
        results = asyncmap(batches, ntasks=ntasks) do batch
            result = process_batch_limited(batch)
            verbose && next!(progress)
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

# Helper function to create a Google Gecko embedder with caching
function create_google_gecko_embedder(;
    project_id::String = get_project_id(),
    location::String = "us-central1",
    model::String = "text-embedding-large-exp-03-07", # "text-embedding-005",
    task_type::String = "RETRIEVAL_DOCUMENT",
    output_dimensionality::Union{Int, Nothing} = nothing,
    verbose::Bool = true,
    cache_prefix=""
)
    google_embedder = GoogleGeckoEmbedder(; 
        project_id, 
        location, 
        model, 
        task_type, 
        output_dimensionality, 
        verbose
    )
    embedder = CachedBatchEmbedder(; embedder=google_embedder, cache_prefix, verbose)
end

# Create a multilingual embedder specifically
function create_google_multilingual_embedder(;
    project_id::String = get_project_id(),
    location::String = "us-central1",
    model::String = "text-multilingual-embedding-002",
    task_type::String = "RETRIEVAL_DOCUMENT",
    output_dimensionality::Union{Int, Nothing} = nothing,
    verbose::Bool = true,
    cache_prefix="",
)
    create_google_gecko_embedder(;
        project_id,
        location,
        model,
        task_type,
        output_dimensionality,
        verbose,
        cache_prefix,
    )
end

# Create a preview embedder specifically for the preview model
function create_google_preview_embedder(;
    project_id::String = get_project_id(),
    location::String = "us-central1",
    verbose::Bool = true,
    cache_prefix="",
)
    create_google_gecko_embedder(;
        project_id,
        location,
        model="text-multilingual-embedding-preview-0409",
        task_type="RETRIEVAL_DOCUMENT",
        output_dimensionality=nothing,
        verbose,
        cache_prefix,
    )
end

# Update humanize method
humanize(e::GoogleGeckoEmbedder) = "GoogleGecko:$(e.model)"

export create_google_gecko_embedder, create_google_multilingual_embedder, create_google_preview_embedder
