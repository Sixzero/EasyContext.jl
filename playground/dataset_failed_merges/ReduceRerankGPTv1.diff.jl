meld ./src/rerankers/ReduceRerankGPT.jl <(cat <<'EOF'
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
  top_n::Int=10
end

# ... (keep the existing rerank function)

function (reranker::ReduceRankGPTReranker)(result::RAGContext)
    index = RAG.SimpleChunkIndex(result.chunk.sources, result.chunk.contexts)
    reranked = RAG.rerank(reranker, index, result.question, RAG.CandidateChunks(index.id, 1:length(index.chunks), ones(length(index.chunks))); top_n=reranker.top_n)
    new_sources = index.sources[reranked.positions]
    new_contexts = index.chunks[reranked.positions]
    return RAGContext(SourceChunk(new_sources, new_contexts), result.question)
end

# ... (keep the rest of the file unchanged)
EOF
)