using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
using HTTP.Exceptions: TimeoutError
const RAG = RAGTools
const PT = PromptingTools

# Helper function to handle model fallback
function aigenerate_with_fallback(prompt; model="dscode", fallback_model="gpt4om", readtimeout=10, kwargs...)
    try
        return aigenerate(prompt; model, http_kwargs=(; readtimeout), kwargs...)
    catch e
        if e isa TimeoutError
            @warn "Model '$model' timed out after $(e). Falling back to '$fallback_model'..."
            return aigenerate(prompt; model=fallback_model, http_kwargs=(; readtimeout=30), kwargs...)
        end
        rethrow(e)
    end
end

Base.@kwdef struct ReduceGPTReranker <: AbstractReranker 
    batch_size::Int=30
    model::AbstractString="dscode"
    max_batch_tokens::Int=40000  # Token limit per batch
    temperature::Float64=0.0
    top_n::Int=10
    rank_gpt_prompt_fn::Function = create_rankgpt_prompt_v2
    verbose::Int=1
    batching_strategy::BatchingStrategy = LinearGrowthBatcher()
    # timeout::Int=3  # Timeout in seconds
end

function (reranker::ReduceGPTReranker)(chunks::OrderedDict{<:AbstractString, <:AbstractString}, query::AbstractString)
    reranked = rerank(reranker, chunks, query)
    return reranked
end

function rerank(
    reranker::ReduceGPTReranker,
    chunks::OrderedDict{<:AbstractString, <:AbstractString},
    query::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Int = reranker.verbose,
    ai_fn::Function = aigenerate_with_fallback,
)
    sources = collect(keys(chunks))
    contents = collect(values(chunks))
    total_docs = length(chunks)
    verbose>1 && @info "Starting RankGPT reranking with reduce for $total_docs documents"
    
    # Rerank function for each batch
    function rerank_batch(doc_batch)
        max_retries = 2
        for attempt in 1:max_retries
            prompt = reranker.rank_gpt_prompt_fn(query, doc_batch, top_n)
            temperature = attempt == 1 ? reranker.temperature : 0.5

            response = ai_fn(prompt; 
                model=reranker.model,
                api_kwargs=(; temperature, top_p=0.1),
                verbose=false
            )
            rankings = extract_ranking(response.content)

            if all(1 .<= rankings .<= length(doc_batch))
                Threads.atomic_add!(cost_tracker, response.cost)
                return rankings
            end
            @info "Invalid rankings (attempt $attempt). Retrying..."
        end
        
        @error "Failed to get valid rankings after $max_retries attempts."
        return 1:length(doc_batch)  # Return sequential ranking as fallback
    end
    
    remaining_doc_idxs = collect(1:total_docs)
    doc_counts = [total_docs]
    iteration_count = 0

    is_last_multibatch = false
    # the reduction
    while length(remaining_doc_idxs) > top_n
        iteration_count += 1
        
        batches = create_batches(
            reranker.batching_strategy,
            contents[remaining_doc_idxs],
            query,
            reranker.rank_gpt_prompt_fn,
            reranker.max_batch_tokens,
            reranker.batch_size;
            verbose=verbose
        )
        
        batch_rankings = asyncmap(batches) do batch_indices
            rankings = rerank_batch(contents[remaining_doc_idxs[batch_indices]])
            if verbose > 1
                selected = remaining_doc_idxs[batch_indices[rankings[1:min(top_n, length(rankings))]]]
                println("\nSelected from batch (source IDs): ", join(sources[selected], ", "))
            end
            return remaining_doc_idxs[batch_indices[rankings]]
        end
        
        is_last_multibatch = sum(arr->length(arr)>0, batch_rankings, init=0) > 1
        # Flatten and take top results from each batch
        idk = [batch[1:min(top_n, length(batch))] for batch in batch_rankings]
        remaining_doc_idxs = reduce(vcat, batch_rankings)
        
        push!(doc_counts, length(remaining_doc_idxs))
        
        # Check if we're stuck (no reduction in document count)
        if length(doc_counts)>1 && doc_counts[end] >= doc_counts[end-1]
            @warn "No reduction in document count detected, forcing final rerank."
            break
        end
    end

    if is_last_multibatch
        # We will do a final rerank, to let the model have full context in the last decision.
        verbose > 1 && @info "Final rerank to get the top $top_n documents."
        # Final ranking of the remaining documents
        final_rankings = rerank_batch(contents[remaining_doc_idxs])
        remaining_doc_idxs = remaining_doc_idxs[final_rankings]
        push!(doc_counts, length(remaining_doc_idxs))
    end
    final_top_n = remaining_doc_idxs[1:min(top_n, length(remaining_doc_idxs))]
    
    reranked_sources = sources[final_top_n]
    reranked_chunks = contents[final_top_n]
    
    if cost_tracker[] > 0 || verbose > 0
        doc_count_str = join(doc_counts, " > ")
        total_cost = round(cost_tracker[], digits=4)
        println("RankGPT document reduction: $doc_count_str Total cost: \$$(total_cost)")
    end
    
    return OrderedDict(zip(reranked_sources, reranked_chunks))
end

# Maintain compatibility with the existing RAG.rerank method
function RAG.rerank(
    reranker::ReduceGPTReranker,
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
    reranked = rerank(reranker, OrderedDict(zip(sources, documents)), question; top_n, cost_tracker, verbose)
    
    reranked_positions = findall(s -> haskey(reranked, s), sources)
    reranked_scores = [1.0 / i for i in 1:length(reranked_positions)]
    
    if candidates isa MultiCandidateChunks
        reranked_ids = [candidates.index_ids[i] for i in reranked_positions]
        return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
    else
        return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
    end
end
