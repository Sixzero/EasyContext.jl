using PromptingTools.Experimental.RAGTools: AbstractContextBuilder, AbstractCandidateChunks, AbstractDocumentIndex, AbstractRAGResult
using PromptingTools.Experimental.RAGTools

RT = RAGTools

struct SimpleContextJoiner <: AbstractContextBuilder end

function RT.build_context(contexter::SimpleContextJoiner,
        index::AbstractDocumentIndex, candidates::AbstractCandidateChunks;
        verbose::Bool = true, kwargs...)
    
    context = String[]
    for (i, position) in enumerate(RT.positions(candidates))
        id = candidates isa MultiCandidateChunks ?  candidates.index_ids[i] : candidates.index_id
        index_ = index isa AbstractChunkIndex ? index : index[id]
        isnothing(index_) && @warn "Missing chunk?" && continue
        
        chunk = RT.chunks(RT.parent(index_))[position]
        toadd = "$(i). $(chunk)"
        push!(context, toadd)
    end
    return context
end
# Mutating version that dispatches on the result to the underlying implementation
function RT.build_context!(contexter::SimpleContextJoiner, index::AbstractDocumentIndex, result::AbstractRAGResult; kwargs...)
  result.context = RT.build_context(contexter, index, result.reranked_candidates; kwargs...)
  return result
end
