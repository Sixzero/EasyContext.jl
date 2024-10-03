using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using DataStructures: OrderedDict


struct SimpleAppender <: CombinationMethod end
struct WeightedCombiner <: CombinationMethod 
    weights::Vector{Float64}
end
struct RRFCombiner <: CombinationMethod end

@kwdef mutable struct CombinedIndexBuilder <: AbstractIndexBuilder
    builders::Vector{<:AbstractIndexBuilder}
    top_k::Int = 300
    combination_method::CombinationMethod = SimpleAppender()
end

function cache_key(builder::CombinedIndexBuilder, args...)
    builder_hashes = [cache_key(b, args...) for b in builder.builders]
    return bytes2hex(sha256("CombinedIndexBuilder_$(join(builder_hashes, "_"))"))
end

function cache_filename(builder::CombinedIndexBuilder, key::String)
    return "combined_index_$key.jld2"
end

function get_index(builder::CombinedIndexBuilder, chunks::OrderedDict{String, String}; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    indices = [get_index(b, chunks; cost_tracker, verbose) for b in builder.builders]
    
    # Check if all indexes have the same sources
    sources = RAG.sources(indices[1])
    if !all(RAG.sources(index) == sources for index in indices[2:end])
        error("All indexes must have the same sources")
    end
    
    return indices
end

# Helper function to get positions and scores using dispatch
function get_positions_and_scores(finder::RAG.CosineSimilarity, builder::AbstractIndexBuilder, index, query, top_k)
    embedder = get_embedder(builder)
    query_emb = RAG.get_embeddings(embedder, [query])
    # Ensure query_emb is a vector
    query_emb = query_emb isa AbstractVector ? query_emb : reshape(query_emb, :)
    RAG.find_closest(finder, RAG.chunkdata(index), query_emb; top_k=top_k)
end

function get_positions_and_scores(finder::RAG.BM25Similarity, builder::AbstractIndexBuilder, index, query, top_k)
    processor = get_processor(builder)
    query_tokens = RAG.get_keywords(processor, [query]; return_keywords=true)[1]
    RAG.find_closest(finder, RAG.chunkdata(index), Float32[], query_tokens; top_k=top_k)
end

function (builder::CombinedIndexBuilder)(chunks::OrderedDict{String, String}, query::AbstractString)
    indexes = get_index(builder, chunks)
    
    # Get results from each index
    all_results = []
    for (i, index) in enumerate(indexes)
        finder = get_finder(builder.builders[i])
        
        positions, scores = get_positions_and_scores(finder, builder.builders[i], index, query, length(RAG.sources(indexes[1])))
        push!(all_results, (positions=positions, scores=scores))
    end

    # Combine results using the specified method
    combined_positions, combined_scores = combine_results(builder.combination_method, all_results, length(RAG.sources(indexes[1])))

    # Apply top_k cut
    top_k = min(builder.top_k, length(combined_positions))
    top_k_positions = combined_positions[1:top_k]
    top_k_scores = combined_scores[1:top_k]

    # Use the first index to get the sources and chunks (since they're the same for all indexes)
    first_index = indexes[1]
    candidates = RAG.CandidateChunks(RAG.indexid(first_index), top_k_positions, top_k_scores)
    sources = first_index[candidates, :sources]
    chunks = first_index[candidates, :chunks]

    return OrderedDict(zip(sources, chunks))
end

# Implement combination methods

function combine_results(::SimpleAppender, all_results, total_positions)
    all_positions = vcat([r.positions for r in all_results]...)
    all_scores = vcat([r.scores for r in all_results]...)
    
    # Sort positions and scores together, keeping original order for equal scores
    sorted_indices = sortperm(all_scores, rev=true)
    sorted_positions = all_positions[sorted_indices]
    sorted_scores = all_scores[sorted_indices]
    
    # Use unique to keep only the first occurrence of each position
    unique_indices = unique(i -> sorted_positions[i], eachindex(sorted_positions))
    
    final_positions = sorted_positions[unique_indices]
    final_scores = sorted_scores[unique_indices]
    
    return final_positions, final_scores
end

function combine_results(combiner::WeightedCombiner, all_results, total_positions)
    combined_scores = zeros(Float64, total_positions)
    for (result, weight) in zip(all_results, combiner.weights)
        for (pos, score) in zip(result.positions, result.scores)
            combined_scores[pos] += score * weight
        end
    end
    sorted_indices = sortperm(combined_scores, rev=true)
    return sorted_indices, combined_scores[sorted_indices]
end

function combine_results(::RRFCombiner, all_results, total_positions)
    k_rrf = 60  # RRF parameter, could be made configurable
    all_positions = [r.positions for r in all_results]
    all_scores = [r.scores for r in all_results]
    
    merged_positions, merged_scores = RAG.reciprocal_rank_fusion(all_positions..., all_scores...; k=k_rrf)
    
    return merged_positions, collect(values(merged_scores))
end

function create_combined_index_builder(;
    embedding_model::String = "text-embedding-3-small",
    top_k::Int = 300,
    combination_method::CombinationMethod = SimpleAppender(),
)
    embedding_builder = EmbeddingIndexBuilder(
        embedder = CachedBatchEmbedder(;embedder=OpenAIBatchEmbedder(; model=embedding_model)),
        top_k = top_k
    )
    bm25_builder = BM25IndexBuilder()
    
    builders = [embedding_builder, bm25_builder]
    
    CombinedIndexBuilder(
        builders = builders,
        top_k = top_k,
        combination_method = combination_method
    )
end

export CombinedIndexBuilder, create_combined_index_builder


