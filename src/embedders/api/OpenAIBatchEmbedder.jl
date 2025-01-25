
using PromptingTools.Experimental.RAGTools: BatchEmbedder, AbstractEmbedder
using PromptingTools: MODEL_EMBEDDING
using SparseArrays

@kwdef struct OpenAIBatchEmbedder <: AbstractEasyEmbedder
    embedder::BatchEmbedder=BatchEmbedder()
    model::String=MODEL_EMBEDDING
end

# Delegate the get_embeddings method to the internal BatchEmbedder
function get_embeddings(embedder::OpenAIBatchEmbedder, docs::AbstractVector{<:AbstractString}; kwargs...)
    get_embeddings(embedder.embedder, docs; model=embedder.model, kwargs...)
end

get_model_name(embedder::OpenAIBatchEmbedder) = embedder.model

# Add this at the end of the file
function create_openai_embedder(;
    model::String = "text-embedding-3-small",
    top_k::Int = 300,
    cache_prefix="",
)
    embedder = CachedBatchEmbedder(; embedder=OpenAIBatchEmbedder(; model=model), cache_prefix)
    # EmbedderSearch(embedder=embedder, top_k=top_k)
end

export create_openai_embedder

# TODO based on thsi implemetn an improved version of get_embeddings ::BatchEmbedder
# function get_embeddings(embedder::BatchEmbedder, docs::AbstractVector{<:AbstractString};
#     verbose::Bool = true,
#     model::AbstractString = PT.MODEL_EMBEDDING,
#     truncate_dimension::Union{Int, Nothing} = nothing,
#     cost_tracker = Threads.Atomic{Float64}(0.0),
#     target_batch_size_length::Int = 80_000,
#     ntasks::Int = 4 * Threads.nthreads(),
#     kwargs...)
# @assert !isempty(docs) "The list of docs to get embeddings from should not be empty."

# ## check if extension is available
# ext = Base.get_extension(PromptingTools, :RAGToolsExperimentalExt)
# if isnothing(ext)
#     error("You need to also import LinearAlgebra, Unicode, SparseArrays to use this function")
# end
# verbose && @info "Embedding $(length(docs)) documents..."
# # Notice that we embed multiple docs at once, not one by one
# # OpenAI supports embedding multiple documents to reduce the number of API calls/network latency time
# # We do batch them just in case the documents are too large (targeting at most 80K characters per call)
# avg_length = sum(length.(docs)) / length(docs)
# embedding_batch_size = floor(Int, target_batch_size_length / avg_length)
# embeddings = asyncmap(Iterators.partition(docs, embedding_batch_size);
#     ntasks) do docs_chunk
#     msg = aiembed(docs_chunk,
#         # LinearAlgebra.normalize but imported in RAGToolsExperimentalExt
#         _normalize;
#         model,
#         verbose = false,
#         kwargs...)
#     Threads.atomic_add!(cost_tracker, msg.cost) # track costs
#     msg.content
# end
# ## Concat across documents and truncate if needed
# embeddings = hcat_truncate(embeddings, truncate_dimension; verbose)
# ## Normalize embeddings
# verbose && @info "Done embedding. Total cost: \$$(round(cost_tracker[],digits=3))"
# return embeddings
# end

# Update humanize method
humanize(e::OpenAIBatchEmbedder) = "OpenAI:$(e.model)"
