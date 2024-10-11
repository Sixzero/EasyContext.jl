using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
const RAG = RAGTools
const PT = PromptingTools

export ReduceRankGPTReranker

Base.@kwdef struct ReduceRankGPTReranker <: AbstractReranker 
    batch_size::Int=30
    model::AbstractString=PT.MODEL_CHAT
    max_tokens::Int=4096
    temperature::Float64=0.0
    verbose::Bool=true
    top_n::Int=10
end

function (reranker::ReduceRankGPTReranker)(chunks::OrderedDict{<:AbstractString, <:AbstractString}, query::AbstractString)
    reranked = rerank(reranker, chunks, query)
    return reranked
end

function rerank(
    reranker::ReduceRankGPTReranker,
    chunks::OrderedDict{<:AbstractString, <:AbstractString},
    query::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = reranker.verbose
)
    sources = collect(keys(chunks))
    contents = collect(values(chunks))
    total_docs = length(chunks)
    batch_size = reranker.batch_size
    batch_size < top_n * 2 && @warn "Batch_size $batch_size should be at least twice bigger than top_n $top_n"
    verbose && @info "Starting RankGPT reranking with reduce for $total_docs documents"
    
    # Rerank function for each batch
    function rerank_batch(doc_batch)
        max_retries = 2
        for attempt in 1:max_retries
            prompt = create_rankgpt_prompt(query, doc_batch, top_n)
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
    doc_counts = [total_docs]

    is_last_multibatch = false
    # the reduction
    while length(remaining_docs) > top_n
        batches = [remaining_docs[i:min(i+batch_size-1, end)] for i in 1:batch_size:length(remaining_docs)]
        
        batch_rankings = asyncmap(batches) do batch_indices
            rankings = rerank_batch(contents[batch_indices])
            return batch_indices[rankings]
        end
        is_last_multibatch = length(batches) > 1
        # Flatten and take top results from each batch
        remaining_docs = reduce(vcat, [batch[1:min(top_n, length(batch))] for batch in batch_rankings])
        
        push!(doc_counts, length(remaining_docs))
    end

    if is_last_multibatch
        # We will do a final rerank, to let the model have full context in the last decision.
        @info "Final rerank to get the top $top_n documents."
        # Final ranking of the remaining documents
        final_rankings = rerank_batch(contents[remaining_docs])
        remaining_docs = remaining_docs[final_rankings]
        push!(doc_counts, length(remaining_docs))
    end
    final_top_n = remaining_docs[1:min(top_n, length(remaining_docs))]
    
    reranked_sources = sources[final_top_n]
    reranked_chunks = contents[final_top_n]
    
    if verbose
        doc_count_str = join(doc_counts, " > ")
        total_cost = round(cost_tracker[], digits=4)
        println("RankGPT document reduction: $doc_count_str Total cost: \$$(total_cost)")
    end
    
    return OrderedDict(zip(reranked_sources, reranked_chunks))
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


