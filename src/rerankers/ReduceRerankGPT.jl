using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
const RAG = RAGTools
const PT = PromptingTools

Base.@kwdef struct ReduceRankGPTReranker <: AbstractReranker 
    batch_size::Int=30
    model::AbstractString=PT.MODEL_CHAT
    max_tokens::Int=4096
    temperature::Float64=0.0
    verbose::Bool=true
    top_n::Int=10
end

function (reranker::ReduceRankGPTReranker)(result::RAGContext, args...)
    reranked = rerank(reranker, result.chunk.sources, result.chunk.contexts, result.question)
    return RAGContext(SourceChunk(reranked.sources, reranked.contexts), result.question)
end

function rerank(
    reranker::ReduceRankGPTReranker,
    sources::AbstractVector{<:AbstractString},
    chunks::AbstractVector{<:AbstractString},
    question::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = reranker.verbose
)
    total_docs = length(chunks)
    batch_size = reranker.batch_size
    batch_size < top_n * 2 && @warn "Batch_size $batch_size should be at least twice bigger than top_n $top_n"
    verbose && @info "Starting RankGPT reranking with reduce for $total_docs documents"
    
    # Rerank function for each batch
    function rerank_batch(doc_batch)
        max_retries = 2
        for attempt in 1:max_retries
            prompt = create_rankgpt_prompt(question, doc_batch, top_n)
            response = aigenerate(prompt; model=reranker.model, max_tokens=reranker.max_tokens, temperature=reranker.temperature, verbose=false)

            rankings = extract_ranking(response.content)
            if all(1 .<= rankings .<= length(doc_batch))
                Threads.atomic_add!(cost_tracker, response.cost)
                return rankings
            end
            
            attempt < max_retries && @warn "Invalid rankings (attempt $attempt). Retrying..."
        end
        
        @error "Failed to get valid rankings after $max_retries attempts."
        return 1:length(doc_batch)  # Return sequential ranking as fallback
    end
    
    remaining_docs = collect(1:total_docs)

    # the reduction
    while length(remaining_docs) > top_n
        batches = [remaining_docs[i:min(i+batch_size-1, end)] for i in 1:batch_size:length(remaining_docs)]
        
        batch_rankings = asyncmap(batches) do batch_indices
            rankings = rerank_batch(chunks[batch_indices])
            return batch_indices[rankings]
        end
        
        # Flatten and take top results from each batch
        remaining_docs = reduce(vcat, [batch[1:min(top_n, length(batch))] for batch in batch_rankings])
        
        verbose && @info "Reduced to $(length(remaining_docs)) documents"
    end

    # Final ranking of the remaining documents
    final_rankings = rerank_batch(chunks[remaining_docs])
    final_top_n = remaining_docs[final_rankings][1:min(top_n, length(final_rankings))]
    
    reranked_sources = sources[final_top_n]
    reranked_chunks = chunks[final_top_n]
    
    verbose && @info "Reranking completed. Total cost: \$$(cost_tracker[])"
    
    return (sources=reranked_sources, contexts=reranked_chunks)
end

# Maintain compatibility with the existing RAG.rerank method
function RAG.rerank(
    reranker::ReduceRankGPTReranker,
    index::AbstractDocumentIndex,
    question::AbstractString,
    candidates::AbstractCandidateChunks;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = reranker.verbose,
    kwargs...
)
    documents = index[candidates, :chunks]
    sources = index[candidates, :sources]
    reranked = rerank(reranker, sources, documents, question; top_n, cost_tracker, verbose)
    
    reranked_positions = findall(s -> s in reranked.sources, sources)
    reranked_scores = [1.0 / i for i in 1:length(reranked_positions)]
    
    if candidates isa MultiCandidateChunks
        reranked_ids = [candidates.index_ids[i] for i in reranked_positions]
        return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
    else
        return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
    end
end

# Helper function to create the RankGPT prompt
function create_rankgpt_prompt(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
    top_n = min(top_n, length(documents))
    document_context = join(["<doc id=\"$i\">$doc</doc>" for (i, doc) in enumerate(documents)], "\n")
    prompt = """
  <question>$question</question>

  <instruction>
  Rank the following documents based on their relevance to the question. 
  Output only the rankings as a comma-separated list of document ids, where the 1st is the most relevant.
  At max select the top_$(top_n) docs, fewer is also okay. You can return an empty list [] if nothing is relevant.
  Only use document ids between 1 and $(length(documents)).
  If a selected document uses a function we probably need, it's preferred to include it in the ranking.
  </instruction>

  <documents>
  $document_context
  </documents>

  <output_format>
  [Rankings, comma-separated list of document ids]
  </output_format>
  """
    return prompt
end


