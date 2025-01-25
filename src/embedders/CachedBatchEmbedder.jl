using SHA
using Parameters
using PromptingTools.Experimental.RAGTools: AbstractEmbedder
using PromptingTools: MODEL_EMBEDDING
using Dates
using Arrow
using DataFrames

@kwdef mutable struct CacheData
    cache::Dict{String, Dict{String, Vector{Float32}}} = Dict{String, Dict{String, Vector{Float32}}}()
    file_locks::Dict{String, ReentrantLock} = Dict{String, ReentrantLock}()
    latest_tasks::Dict{String, Task} = Dict{String, Task}()
end


const CACHE_STATE = CacheData()

@kwdef struct CachedBatchEmbedder <: AbstractEmbedder
    embedder::AbstractEmbedder = OpenAIBatchEmbedder()
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

function get_score(builder::CachedBatchEmbedder, chunks::AbstractVector{T}, query::AbstractString; cost_tracker = Threads.Atomic{Float64}(0.0)) where {T}
    embeddings = RAG.get_embeddings(builder, chunks; cost_tracker)
    query_emb = RAG.get_embeddings(builder, [query]; cost_tracker)
    get_score(Val(:CosineSimilarity), embeddings, reshape(query_emb, :))
end

get_embedder(embedder::CachedBatchEmbedder) = get_embedder(embedder.embedder)
get_embedder_uniq_id(embedder::CachedBatchEmbedder) = get_embedder_uniq_id(embedder.embedder)
get_model_name(embedder::CachedBatchEmbedder) = get_model_name(get_embedder(embedder))

function load_cache(cache_file)
    !isfile(cache_file) && return Dict{String, Vector{Float32}}()
    
    df = Arrow.Table(cache_file) |> DataFrame
    Dict(zip(df.hash, df.embedding))
end

function safe_append_cache(cache_file::String, new_entries::Dict{String,Vector{Float32}})
    if isempty(new_entries) return end
    
    @async_showerr lock(get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)) do
        df = DataFrame(
            hash = collect(keys(new_entries)),
            embedding = collect(values(new_entries))
        )
        Arrow.append(cache_file, df)
    end
end

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractChunk};
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads())
    docs_str = string.(docs) # TODO maybe we could do this later to allocate even less?

    get_embeddings(
        embedder, docs_str; cost_tracker, target_batch_size_length,ntasks,
    )
end

function get_embeddings(embedder::CachedBatchEmbedder, docs::AbstractVector{<:AbstractString};
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads(),
        )
    if isempty(docs)
        verbose && @info "No documents to embed."
        return Matrix{Float32}(undef, 0, 0)
    end

    model = get_model_name(embedder)::String
    unique_name = get_embedder_uniq_id(embedder)
    cache_prefix, truncate_dimension = embedder.cache_prefix, embedder.truncate_dimension
    
    cache_file = joinpath(embedder.cache_dir, cache_prefix * "embeddings_$(unique_name).arrow")
    
    # Load cache
    if !haskey(CACHE_STATE.cache, cache_file)
        lock(get!(ReentrantLock, CACHE_STATE.file_locks, cache_file)) do
            if !haskey(CACHE_STATE.cache, cache_file)
                CACHE_STATE.cache[cache_file] = load_cache(cache_file)
            end
        end
    end
    
    cache = CACHE_STATE.cache[cache_file]
    doc_hashes = [bytes2hex(sha1(doc)) for doc in docs]
    to_embed_indices = findall(i -> !haskey(cache, doc_hashes[i]), eachindex(docs))
    
    if !isempty(to_embed_indices)
        docs_to_embed = docs[to_embed_indices]
        new_embeddings::Matrix{Float32} = get_embeddings(embedder.embedder, docs_to_embed;
            verbose=embedder.verbose, model, truncate_dimension, cost_tracker,
            target_batch_size_length, ntasks)

        # Update cache with new embeddings
        # we might be able to not materialize this and everything would still work.
        new_entries = Dict(doc_hashes[idx] => new_embeddings[:, i] 
                         for (i, idx) in enumerate(to_embed_indices))
        
        # Update memory cache
        merge!(cache, new_entries)
        
        # Append to Arrow file
        safe_append_cache(cache_file, new_entries)
    end
    
    # Create all_embeddings array
    embedding_dim = length(first(values(cache)))
    all_embeddings = zeros(Float32, embedding_dim, length(docs))
    
    for (i, hash) in enumerate(doc_hashes)
        all_embeddings[:, i] = cache[hash]
    end
    
    if embedder.verbose
        cached_count = length(docs) - length(to_embed_indices)
        cost_text = length(to_embed_indices) > 0 ? " Cost: \$$(round(cost_tracker[], digits=3))" : ""
        @info "Embedding complete. $cached_count docs from cache, $(length(to_embed_indices)) newly embedded." * cost_text
    end

    return all_embeddings
end

# Add transparent humanize method
humanize(e::CachedBatchEmbedder) = humanize(e.embedder)
