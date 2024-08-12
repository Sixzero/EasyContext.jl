using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
const RAG = RAGTools
const PT = PromptingTools

Base.@kwdef struct ReduceRankGPTReranker <: AbstractReranker 
  batch_size::Int=20
  api_key::AbstractString=PT.OPENAI_API_KEY
  model::AbstractString=PT.MODEL_CHAT
  max_tokens::Int=4096
  temperature::Float64=0.0
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
  verbose::Bool = false,
  kwargs...
)
  batch_size, model, api_key, max_tokens, temperature = reranker.batch_size, reranker.model, reranker.api_key, reranker.max_tokens, reranker.temperature
  documents = index[candidates, :chunks]
  total_docs = length(documents)
  batch_size < top_n * 2 && @warn "Batch_size $batch_size should be at least twice bigger than top_n $top_n"
  verbose && @info "Starting RankGPT reranking with reduce for $total_docs documents"
  
  
  # Rerank function for each batch
  function rerank_batch(doc_batch)
      prompt = create_rankgpt_prompt(question, doc_batch, top_n)
      response = aigenerate(prompt; model=model, api_key=api_key, max_tokens=max_tokens, temperature=temperature)
      
      # Parse the response to get rankings
      rankings = extract_ranking(response.content)
      @assert all(rankings .>= 1) "Not every index is larger than 1! Prompt:$prompt\nResp: $(response.content)"
      # Update cost tracker
      Threads.atomic_add!(cost_tracker, response.cost)
      
      return rankings
  end
  
  remaining_docs = collect(1:total_docs)

  # the reduction
  while length(remaining_docs) > top_n
      batches = [remaining_docs[i:min(i+batch_size-1, end)] for i in 1:batch_size:length(remaining_docs)]
      
      batch_rankings = asyncmap(batches) do batch_indices
          rankings = rerank_batch(documents[batch_indices])
          @info "We found $(length(rankings)) rankings from batch $(length(batch_indices))"
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
  
  verbose && @info "Reranking completed. Total cost: $(cost_tracker[]) tokens"
  
  # Return the reranked candidates
  if candidates isa MultiCandidateChunks
      reranked_ids = [candidates.ids[i] for i in final_top_n]
      return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
  else
      return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
  end
end

# Helper function to create the RankGPT prompt
function create_rankgpt_prompt(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  prompt = """
  Given the question: "$question"
  Rank the following documents based on their relevance to the question. 
  Output only the rankings as a comma-separated list of indices, where 1 is the most relevant. At max select top_$top_n docs, but less is also okay, you can also return nothing [] if nothing is relevant. 
  If a selected file/function uses a function we probably need, then also it is preferred to include it in the ranking.
  Documents:
  $(join(["$i. $doc" for (i, doc) in enumerate(documents)], "\n"))
  Rankings:
  """
  return prompt
end