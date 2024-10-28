using SHA, JLD2
using Parameters
using PromptingTools.Experimental.RAGTools: AbstractEmbedder
using PromptingTools: MODEL_EMBEDDING
using Dates

@kwdef mutable struct CacheData
    cache::Dict{String, Dict{String, Vector{Float32}}} = Dict{String, Dict{String, Vector{Float32}}}()
    file_locks::Dict{String, ReentrantLock} = Dict{String, ReentrantLock}()
    latest_tasks::Dict{String, Task} = Dict{String, Task}()
end

const CACHE_STATE = CacheData()

@kwdef struct CachedBatchEmbedder <: AbstractEmbedder
    embedder::Union{AbstractEmbedder, AbstractIndexBuilder} = OpenAIBatchEmbedder()
    cache_dir::String = let
        current_file = @__FILE__
        default_cache_dir = joinpath(dirname(dirname(dirname(current_file))), "cache")
        isdir(default_cache_dir) || mkpath(default_cache_dir)
        default_cache_dir
    end
    cache_prefix::String=""
    truncate_dimension::Union{Int, Nothing}=nothing
    verbose::Bool=false
end

get_embedder(embedder::CachedBatchEmbedder) = get_embedder(embedder.embedder)
get_embedder_uniq_id(embedder::AbstractIndexBuilder) = get_embedder_uniq_id(embedder.embedder)
get_embedder_uniq_id(embedder::CachedBatchEmbedder) = get_embedder_uniq_id(embedder.embedder)
get_model_name(embedder::CachedBatchEmbedder) = get_model_name(get_embedder(embedder))

# Updated function for safe file saving
function safe_save_cache(cache_file::String, cache::Dict, timestamp::DateTime)
    if haskey(CACHE_STATE.latest_tasks, cache_file)
        task = CACHE_STATE.latest_tasks[cache_file]
        if !istaskdone(task)
            schedule(task, InterruptException(), error=true)
            temp_file = "$(cache_file).tmp"
            isfile(temp_file) && rm(temp_file, force=true)
        end
    end
    
    task = @spawn begin
        temp_file = "$(cache_file).tmp"
        JLD2.save(temp_file, cache)
        lock(get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)) do
            if get(CACHE_STATE.latest_tasks, cache_file, current_task()) == current_task()
                mv(temp_file, cache_file, force=true)
            else
                rm(temp_file, force=true)
            end
        end
    end
    
    CACHE_STATE.latest_tasks[cache_file] = task
end

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractString};
        verbose::Bool = embedder.verbose,
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads())
    
    get_embeddings(embedder, docs,
    verbose,
    cost_tracker,
    target_batch_size_length,
    ntasks,
    )
end

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractString},
    verbose::Bool,
    cost_tracker,
    target_batch_size_length::Int,
    ntasks::Int,
    )
        if isempty(docs)
            verbose && @info "No documents to embed."
            return Matrix{Float32}(undef, 0, 0)
        end
    
        model = get_model_name(embedder)::String
        unique_name = get_embedder_uniq_id(embedder)
        cache_prefix, truncate_dimension = embedder.cache_prefix, embedder.truncate_dimension
        
        cache_file = joinpath(embedder.cache_dir, cache_prefix * "embeddings_$(unique_name).jld2")
        
        # Use the global cache
        if !haskey(CACHE_STATE.cache, cache_file)
            lock(get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)) do
                if !haskey(CACHE_STATE.cache, cache_file)  # Double-check pattern
                    cc = isfile(cache_file) ? JLD2.load(cache_file) : Dict{String, Vector{Float32}}()
                    if length(cc) == 1
                        @warn "This should not really happen cachefile: $cache_file"
                        cc = first(values(cc))
                    end
                    CACHE_STATE.cache[cache_file] = cc
                end
            end
        end
        
        cache = CACHE_STATE.cache[cache_file]
        doc_hashes = [bytes2hex(sha256(doc)) for doc in docs]
        to_embed_indices = findall(i -> !haskey(cache, doc_hashes[i]), eachindex(docs))
        
        if !isempty(to_embed_indices)
            docs_to_embed = docs[to_embed_indices]
            new_embeddings::Matrix{Float32} = get_embeddings(embedder.embedder, docs_to_embed;
                verbose, model, truncate_dimension, cost_tracker,
                target_batch_size_length, ntasks)

            lock(get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)) do
                timestamp = Dates.now()
                for (new_idx, doc_idx) in enumerate(to_embed_indices)
                    cache[doc_hashes[doc_idx]] = new_embeddings[:, new_idx]
                end
                safe_save_cache(cache_file, cache, timestamp)
            end
        end
   
        # Create all_embeddings after potentially updating the cache
        embedding_dim = length(first(values(cache)))
        all_embeddings = zeros(Float32, embedding_dim, length(docs))
        
        for (i, hash) in enumerate(doc_hashes)
            all_embeddings[:, i] = cache[hash]
        end
        
        if verbose
            cached_count = length(docs) - length(to_embed_indices)
            cost_text = length(to_embed_indices) > 0 ? " Cost: \$$(round(cost_tracker[], digits=3))" : ""
            @info "Embedding complete. $cached_count docs from cache, $(length(to_embed_indices)) newly embedded." * cost_text
        end
   
        return all_embeddings
end
