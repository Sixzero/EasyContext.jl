using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
using HTTP.Exceptions: TimeoutError
const PT = PromptingTools

# Model state tracking
Base.@kwdef mutable struct ModelState
    failures::Int = 0
    last_error_type::Union{Nothing,Type} = nothing
    last_error_time::Float64 = 0.0
    available::Bool = true
end

Base.@kwdef mutable struct AIFunctionManager
    models::Vector{String}
    states::Dict{String,ModelState} = Dict{String,ModelState}()
    readtimeout::Int = 15
end

function try_generate(manager::AIFunctionManager, prompt; kwargs...)
    for model in manager.models
        state = get!(manager.states, model, ModelState())
        !state.available && continue
        
        try
            return aigenerate(prompt; model, http_kwargs=(; readtimeout=manager.readtimeout), kwargs...)
        catch e
            state.failures += 1
            state.last_error_type = typeof(e)
            state.last_error_time = time()
            
            if e isa TimeoutError
                @warn "Model '$model' timed out after $(manager.readtimeout)s."
            elseif e isa HTTP.Exceptions.StatusError && e.status == 429
                @warn "Model '$model' rate limited, removing from available models."
                state.available = false
            else
                @warn "Model '$model' failed with: $(typeof(e))"
                rethrow(e)
            end
        end
    end
    error("All models failed or unavailable")
end

Base.@kwdef mutable struct ReduceGPTReranker <: AbstractReranker 
    batch_size::Int=30
    model::AbstractString="dscode"
    max_batch_tokens::Int=64000  # Token limit per batch
    temperature::Float64=0.0
    top_n::Int=10
    rank_gpt_prompt_fn::Function = create_rankgpt_prompt_v2
    verbose::Int=1
    batching_strategy::BatchingStrategy = LinearGrowthBatcher()
    strict_mode::Bool = false  # New parameter for strict model usage
end

function rerank(
    reranker::ReduceGPTReranker,
    chunks::Vector{T},
    query::AbstractString;
    top_n::Int = reranker.top_n,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Int = reranker.verbose,
) where T
    # Initialize AIFunctionManager with model preferences
    ai_manager = AIFunctionManager(
        models=reranker.strict_mode ? [reranker.model] : unique([reranker.model, "gem20f", "gem15f", "dscode", "gpt4om"])
    )
    
    contents = string.(chunks)
    total_docs = length(chunks)
    verbose>1 && @info "Starting RankGPT reranking with reduce for $total_docs documents"
    
    # Rerank function for each batch
    function rerank_batch(doc_batch)
        max_retries = 2
        for attempt in 1:max_retries
            prompt = reranker.rank_gpt_prompt_fn(query, doc_batch, top_n)
            temperature = attempt == 1 ? reranker.temperature : 0.5

            response = try_generate(ai_manager, prompt; 
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
                println("\nSelected from batch (indices): ", join(selected, ", "))
            end
            return remaining_doc_idxs[batch_indices[rankings]]
        end
        
        is_last_multibatch = sum(arr->length(arr)>0, batch_rankings, init=0) > 1
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
    
    if cost_tracker[] > 0 || verbose > 0
        doc_count_str = join(doc_counts, " > ")
        total_cost = round(cost_tracker[], digits=4)
        println("RankGPT document reduction: $doc_count_str Total cost: \$$(total_cost)")
    end
    
    return chunks[final_top_n]
end
