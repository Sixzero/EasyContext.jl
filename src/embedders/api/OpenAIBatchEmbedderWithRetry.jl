using RAGTools: BatchEmbedder, AbstractEmbedder, _normalize
using PromptingTools: MODEL_EMBEDDING
using SparseArrays
using Base.Threads
using PromptingTools
const PT = PromptingTools

@kwdef struct OpenAIBatchEmbedderWithRetry <: AbstractEasyEmbedder
    embedder::BatchEmbedder=BatchEmbedder()
    model::String=MODEL_EMBEDDING
    max_retries::Int=3
    min_chunk_size::Int=10  # Minimum chunk size to try if splitting is needed
end

function get_embeddings(embedder::OpenAIBatchEmbedderWithRetry, docs::AbstractVector{<:AbstractString};
        verbose::Bool = true,
        cost_tracker = Threads.Atomic{Float64}(0.0),
        target_batch_size_length::Int = 80_000,
        ntasks::Int = 4 * Threads.nthreads(),
        kwargs...)
    
    @assert !isempty(docs) "The list of docs to get embeddings from should not be empty."
    verbose && @info "Embedding $(length(docs)) documents..."

    avg_length = sum(length.(docs)) / length(docs)
    embedding_batch_size = floor(Int, target_batch_size_length / avg_length)

    function process_chunk(docs_chunk, chunk_size)
        try
            msg = aiembed(docs_chunk, _normalize;
                model=embedder.model,
                verbose=false,
                kwargs...)
            Threads.atomic_add!(cost_tracker, msg.cost)
            return msg.content
        catch e
            if e isa HTTP.Exceptions.StatusError && e.status == 400 && chunk_size > embedder.min_chunk_size
                # Split the chunk in half and try again
                mid = div(length(docs_chunk), 2)
                chunk1 = docs_chunk[1:mid]
                chunk2 = docs_chunk[mid+1:end]
                
                verbose && @info "Splitting chunk of size $(length(docs_chunk)) into $(length(chunk1)) and $(length(chunk2))"
                
                result1 = process_chunk(chunk1, div(chunk_size, 2))
                result2 = process_chunk(chunk2, div(chunk_size, 2))
                
                return hcat(result1, result2)
            else
                rethrow(e)
            end
        end
    end

    embeddings = asyncmap(Iterators.partition(docs, embedding_batch_size);
        ntasks) do docs_chunk
        process_chunk(collect(docs_chunk), embedding_batch_size)
    end

    result = reduce(hcat, embeddings)
    verbose && @info "Done embedding. Total cost: \$$(round(cost_tracker[], digits=3))"
    return result
end

# Add this at the end of the file
function create_openai_embedder_with_retry(;
    model::String = "text-embedding-3-small",
    cache_prefix="",
)
    embedder = CachedBatchEmbedder(; 
        embedder=OpenAIBatchEmbedderWithRetry(; model=model), 
        cache_prefix
    )
end

export OpenAIBatchEmbedderWithRetry, create_openai_embedder_with_retry
