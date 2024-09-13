using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
const RAG = RAGTools
const PT = PromptingTools

Base.@kwdef struct ReduceRankGPTReranker <: AbstractReranker 
  batch_size::Int=20
  model::AbstractString=PT.MODEL_CHAT
  max_tokens::Int=4096
  temperature::Float64=0.0
  verbose::Bool=true
end
"""
    rerank(
        reranker::ReduceRankGPTReranker,
        index::AbstractDocumentIndex,
        question::AbstractString,
        candidates::AbstractCandidateChunks;
        top_n::Int = length(candidates.scores),
        cost_tracker = Threads.Atomic{Float64}(0.0),
        verbose::Bool = false,
        kwargs...
    )
Rerank candidate chunks using the RankGPT algorithm with a reduce operation for efficient processing of large document sets.
# Arguments
- `reranker::ReduceRankGPTReranker`: The RankGPT reranker instance.
- `index::AbstractDocumentIndex`: The document index containing the chunks.
- `question::AbstractString`: The query used for reranking.
- `candidates::AbstractCandidateChunks`: The candidate chunks to be reranked.
- `top_n::Int`: The number of top-ranked documents to return.
- `cost_tracker`: An atomic counter to track the cost of LLM calls.
- `verbose::Bool`: Whether to print verbose output.
# Returns
A new `AbstractCandidateChunks` object with reranked candidates.
"""
function RAG.rerank(
  reranker::ReduceRankGPTReranker,
  index::AbstractDocumentIndex,
  question::AbstractString,
  candidates::AbstractCandidateChunks;
  top_n::Int = length(candidates.scores),
  cost_tracker = Threads.Atomic{Float64}(0.0),
  kwargs...
)
  
  batch_size, model, max_tokens, temperature, verbose = reranker.batch_size, reranker.model, reranker.max_tokens, reranker.temperature, reranker.verbose

  documents = index[candidates, :chunks]
  total_docs = length(documents)
  batch_size < top_n * 2 && @warn "Batch_size $batch_size should be at least twice bigger than top_n $top_n"
  verbose && @info "Starting RankGPT reranking with reduce for $total_docs documents"
  
  
  # Rerank function for each batch
  function rerank_batch(doc_batch)
      max_retries = 2
      for attempt in 1:max_retries
          prompt = create_rankgpt_prompt(question, doc_batch, top_n)
          response = aigenerate(prompt; model=model, max_tokens=max_tokens, temperature=temperature, verbose=false)

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
          rankings = rerank_batch(documents[batch_indices])
          # @info "We found $(length(rankings)) rankings from batch $(length(batch_indices))"
          return batch_indices[rankings]
      end
      
      # Flatten and take top results from each batch
      remaining_docs = reduce(vcat, [batch[1:min(top_n, length(batch))] for batch in batch_rankings])
      
      verbose && @info "Reduced to $(length(remaining_docs)) documents"
  end

  # Final ranking of the remaining documents
  final_rankings = rerank_batch(documents[remaining_docs])
  final_top_n = remaining_docs[final_rankings][1:min(top_n, length(final_rankings))]
  
  reranked_positions = [candidates.positions[i] for i in final_top_n]
  reranked_scores = [1.0 / i for i in 1:length(final_top_n)]
  
  verbose && @info "Reranking completed. Total cost: \$$(cost_tracker[])"
  
  # Return the reranked candidates
  if candidates isa MultiCandidateChunks
      reranked_ids = [candidates.index_ids[i] for i in final_top_n]
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
