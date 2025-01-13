# Add new abstract type for batching strategies
abstract type BatchingStrategy end

"""
    LinearGrowthBatcher <: BatchingStrategy

A batching strategy that grows batches incrementally while checking token limits.

Benefits:
- Maintains strict document ordering
- More predictable batch sizes
- Better for documents that should stay together sequentially
- More conservative in batch size adjustments
"""
@kwdef struct LinearGrowthBatcher <: BatchingStrategy
    estimation_method::TokenEstimationMethod = CharCountDivTwo
end

"""
    TokenBalancedBatcher <: BatchingStrategy

A batching strategy that sorts documents by size and distributes them to achieve balanced token counts.

Benefits:
- Optimal token count distribution across batches
- Better resource utilization
- Good for parallel processing
- Best for cases where document order doesn't matter
"""
@kwdef struct TokenBalancedBatcher <: BatchingStrategy
    estimation_method::TokenEstimationMethod = CharCountDivTwo
end

function create_batches(strategy::LinearGrowthBatcher, docs, query, prompt_fn, max_tokens, batch_size; verbose=0)
    # First get token counts for all documents
    doc_tokens = map(doc -> estimate_tokens(prompt_fn(query, [doc], 1), strategy.estimation_method), docs)
    
    batches = Vector{UnitRange{Int}}()
    current_start = 1
    
    while current_start <= length(docs)
        # Try to find the largest possible batch starting from current_start
        batch_end = current_start
        batch_tokens = doc_tokens[current_start]
        
        while batch_end < min(current_start + batch_size - 1, length(docs)) &&
              batch_tokens + doc_tokens[batch_end + 1] <= max_tokens
            batch_end += 1
            batch_tokens += doc_tokens[batch_end]
        end
        
        push!(batches, current_start:batch_end)
        current_start = batch_end + 1
    end
    
    if verbose > 1
        println("\nSimple token balancing info:")
        println("Total documents: ", length(docs))
        println("Document token counts: ", join(["doc$(i):$(t)" for (i,t) in enumerate(doc_tokens)], ", "))
        println("Batch sizes: ", join(["batch$(i):$(length(b))" for (i,b) in enumerate(batches)], ", "))
        println("Batch token counts: ", join(["batch$(i):$(sum(doc_tokens[b]))" for (i,b) in enumerate(batches)], ", "))
    end
    
    return batches
end

function create_batches(strategy::TokenBalancedBatcher, docs, query, prompt_fn, max_tokens, batch_size; verbose=0)
    # First get token counts for all documents
    doc_tokens = map(doc -> estimate_tokens(prompt_fn(query, [doc], 1), strategy.estimation_method), docs)
    
    # Calculate number of batches needed
    n_docs = length(docs)
    n_batches = ceil(Int, n_docs / batch_size)
    
    # Sort docs by token count for initial distribution
    sorted_indices = sortperm(doc_tokens, rev=true)
    
    # Initialize batches
    batches = [Int[] for _ in 1:n_batches]
    batch_tokens = zeros(Int, n_batches)
    
    # First pass: distribute documents to minimize token count differences
    for (i, idx) in enumerate(sorted_indices)
        # Find batch with minimum token count
        target_batch = argmin(batch_tokens)
        
        # If adding this doc would exceed max_tokens, try next best batch
        while batch_tokens[target_batch] + doc_tokens[idx] > max_tokens && 
              length(batches[target_batch]) < batch_size
            batch_tokens[target_batch] = typemax(Int)  # Mark as full
            target_batch = argmin(batch_tokens)
            if batch_tokens[target_batch] == typemax(Int)
                # All batches exceed max_tokens, reset to find least loaded
                batch_tokens = [sum(doc_tokens[b]) for b in batches]
                target_batch = argmin(batch_tokens)
                break
            end
        end
        
        push!(batches[target_batch], idx)
        batch_tokens[target_batch] += doc_tokens[idx]
    end
    
    # Remove empty batches
    filter!(!isempty, batches)
    # just in case things would work better in order
    [sort!(b) for b in batches]

    # Add verbose logging
    if verbose > 1
        println("\nToken balancing info:")
        println("Total documents: ", length(docs))
        println("Document token counts: ", join(["doc$(i):$(t)" for (i,t) in enumerate(doc_tokens)], ", "))
        println("Batch sizes: ", join(["batch$(i):$(length(b))" for (i,b) in enumerate(batches)], ", "))
        println("Batch token counts: ", join(["batch$(i):$(sum(doc_tokens[b]))[$(b)]" for (i,b) in enumerate(batches)], ", "))
    end
    
    return batches
end
