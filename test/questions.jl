question = """
\"\"\"
    rerank_reduce(
        reranker::RankGPTReranker,
        index::AbstractDocumentIndex,
        question::AbstractString,
        candidates::AbstractCandidateChunks;
        api_key::AbstractString = PT.OPENAI_API_KEY,
        model::AbstractString = PT.MODEL_CHAT,
        batch_size::Int = 10,
        top_n::Int = length(candidates.scores),
        max_tokens::Int = 4096,
        temperature::Float64 = 0.0,
        cost_tracker = Threads.Atomic{Float64}(0.0),
        verbose::Bool = false,
        kwargs...
    )
Rerank candidate chunks using the RankGPT algorithm with a reduce operation for efficient processing of large document sets.
# Arguments
- `reranker::RankGPTReranker`: The RankGPT reranker instance.
- `index::AbstractDocumentIndex`: The document index containing the chunks.
- `question::AbstractString`: The query used for reranking.
- `candidates::AbstractCandidateChunks`: The candidate chunks to be reranked.
- `api_key::AbstractString`: The API key for the LLM service.
- `model::AbstractString`: The LLM model to use for reranking.
- `batch_size::Int`: The number of documents to process in each batch.
- `top_n::Int`: The number of top-ranked documents to return.
- `max_tokens::Int`: The maximum number of tokens for each LLM call.
- `temperature::Float64`: The temperature setting for the LLM.
- `cost_tracker`: An atomic counter to track the cost of LLM calls.
- `verbose::Bool`: Whether to print verbose output.
# Returns
A new `AbstractCandidateChunks` object with reranked candidates.
\"\"\"
function rerank_reduce(
  reranker::RankGPTReranker,
  index::AbstractDocumentIndex,
  question::AbstractString,
  candidates::AbstractCandidateChunks;
  api_key::AbstractString = PT.OPENAI_API_KEY,
  model::AbstractString = PT.MODEL_CHAT,
  batch_size::Int = 10,
  top_n::Int = length(candidates.scores),
  max_tokens::Int = 4096,
  temperature::Float64 = 0.0,
  cost_tracker = Threads.Atomic{Float64}(0.0),
  verbose::Bool = false,
  kwargs...
)
  documents = index[candidates, :chunks]
  total_docs = length(documents)
  
  verbose && @info "Starting RankGPT reranking with reduce for \$total_docs documents"
  
  batches = [documents[i:min(i+batch_size-1, end)] for i in 1:batch_size:total_docs]
  
  function rerank_batch(batch)
      prompt = create_rankgpt_prompt(question, batch)
      response = aigenerate(prompt; model=model, api_key=api_key, max_tokens=max_tokens, temperature=temperature)
      
      # Parse the response to get rankings
      rankings = parse_rankgpt_response(response.content)
      
      # Update cost tracker
      Threads.atomic_add!(cost_tracker, response.cost)
      
      return rankings
  end
  
  batch_rankings = asyncmap(rerank_batch, batches)
  
  top_from_batches = reduce(vcat, [batch[1:min(top_n, length(batch))] for batch in batch_rankings])
  
  if length(top_from_batches) > top_n
      # Rerank the combined top results
      final_rankings = rerank_batch(documents[top_from_batches])
      final_top_n = final_rankings[1:top_n]
  else
      final_top_n = top_from_batches
  end
  
  reranked_positions = [candidates.positions[i] for i in final_top_n]
  reranked_scores = [1.0 / i for i in 1:length(final_top_n)]  # Use reciprocal rank as score
  
  verbose && @info "Reranking completed. Total cost: \$(cost_tracker[]) tokens"
  
  if candidates isa MultiCandidateChunks
      reranked_ids = [candidates.ids[i] for i in final_top_n]
      return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
  else
      return CandidateChunks(candidates.id, reranked_positions, reranked_scores)
  end
end

function create_rankgpt_prompt(question::AbstractString, documents::Vector{<:AbstractString})
  prompt = \"\"\"
  Given the question: \"$question"
  Rank the following documents based on their relevance to the question. 
  Output only the rankings as a comma-separated list of indices, where 1 is the most relevant.
  Documents:
  \$(join(["\$i. \$doc" for (i, doc) in enumerate(documents)], "n"))
  Rankings:
  \"\"\"
  return prompt
end
# Helper function to parse the RankGPT response
function parse_rankgpt_response(response::AbstractString)
  try
      return parse.(Int, split(strip(response), ","))
  catch e
      @warn "Failed to parse RankGPT response: \$response"
      return []
  end
end

I would need to run the reduction until I end up with the top_n results. Actually I don't even need more. So like a piramid I would need to call the asyncmap in a loop until I get the top_n results.
"""
question="""
Get me the fastest reduce(vcat, listoflist) you can think of.
Is copyto not the fastest?

function fast_vcat(listoflist)
  result = Vector{eltype(eltype(listoflist))}(undef, sum(length, listoflist))
  offset = 1
  @inbounds for list in listoflist
      copyto!(result, offset, list, 1, length(list))
      offset += length(list)
  end
  result
end

This next runs a little bit faster:
fast_vcat2(mylist) = begin  
    alloc = Vector{eltype(eltype(mylist))}(undef, sum(length, mylist))
    idx = 1
    @inbounds for v in mylist
        for v_val in v
            alloc[idx] = v_val
            idx += 1
        end
    end
    alloc
end
"""
question = """

function get_chunks(chunker::AbstractChunker,
  files_or_docs::Vector{<:AbstractString};
  sources::AbstractVector{<:AbstractString} = files_or_docs,
  verbose::Bool = true,
  separators = ["\n\n", ". ", "\n", " "], max_length::Int = 256)

# Check that all items must be existing files or strings
@assert (length(sources)==length(files_or_docs)) "Length of `sources` must match length of `files_or_docs`"

output_chunks = Vector{SubString{String}}()
output_sources = Vector{eltype(sources)}()

# Do chunking first
for i in eachindex(files_or_docs, sources)
  doc_raw, source = load_text(chunker, files_or_docs[i]; source = sources[i])
  isempty(doc_raw) && continue
  # split into chunks by recursively trying the separators provided
  # if you want to start simple - just do `split(text,"\n\n")`
  doc_chunks = PT.recursive_splitter(doc_raw, separators; max_length) .|> strip |>
               x -> filter(!isempty, x)
  # skip if no chunks found
  isempty(doc_chunks) && continue
  append!(output_chunks, doc_chunks)
  append!(output_sources, fill(source, length(doc_chunks)))
end

return output_chunks, output_sources
end

I would need an get_chunks AbstractChunker which doesn't split up files into multiple chunks. And doesn't split files. I need a struct FullFileChunker implemented.
"""
question = """
I would need an get_chunks AbstractChunker which doesn't split up files into multiple chunks. And doesn't split files. I need a struct FullFileChunker implemented.
""" # This have to find load_text and get_chunks
question = """
using PromptingTools.Experimental.RAGTools
const RAG = RAGTools

struct FullFileChunker <: AbstractChunker end

function RAG.get_chunks(chunker::FullFileChunker,
                    files_or_docs::Vector{<:AbstractString};
                    sources::AbstractVector{<:AbstractString} = files_or_docs,
                    verbose::Bool = true)
    
    @assert length(sources) == length(files_or_docs) "Length of `sources` must match length of `files_or_docs`"
    output_chunks = Vector{String}()
    output_sources = Vector{eltype(sources)}()
    for i in eachindex(files_or_docs, sources)
        doc_raw, source = RAG.load_text(chunker, files_or_docs[i]; source = sources[i])
        isempty(doc_raw) && (@warn("Missing content \$(files_or_docs[i])"); continue)
        
        push!(output_chunks, doc_raw)
        push!(output_sources, source)
    end
    return output_chunks, output_sources
end
function RAG.load_text(chunker::FullFileChunker, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    @assert isfile(input) "Path \$input does not exist"
    return read(input, String), source
end

I would also need to add recursive_splitting to this solution, but I would want sources to contain the line numbers where the chunks are coming from. 
"""
question = """

file_indexer = SimpleIndexer(;chunker, embedder=NoEmbedder())
files_index = build_index(file_indexer, files)

reranker = ReduceRankGPTReranker(;batch_size=batchsize, model="gpt4om")  # or RankGPTReranker(), or FlashRanker(model)
retriever = RAG.AdvancedRetriever(;reranker, rephraser=JuliacodeRephraser(), )

result = retrieve(retriever, files_index, question; 
    kwargs.retriever_kwargs..., 
    embedder_kwargs=(model = file_indexer.embedder.model,), 
    top_k=100,  # number of initial candidates
    top_n=5     # number of final reranked results
)

Is there a way to run this with NoEmbedder but just with a reranker? So the ReduceRankGPTReranker runs on every chunk.
"""
question = """

file_indexer = SimpleIndexer(;chunker, embedder=NoEmbedder())
files_index = build_index(file_indexer, files)

retriever = SimpleRetriever(;
  embedder=NoEmbedder(), 
  reranker = ReduceRankGPTReranker(;batch_size=batchsize, model="gpt4om"))

result = retrieve(retriever, files_index, question; 
  # kwargs.retriever_kwargs..., 
  top_k = length(files_index),  # This will fetch all chunks
  top_n = 5     # number of final reranked results
)

Is there a way to run this with NoEmbedder but just with a reranker? So the ReduceRankGPTReranker runs on every chunk.
MethodError: no method matching find_closest(::PromptingTools.Experimental.RAGTools.CosineSimilarity, ::PromptingTools.Experimental.RAGTools.ChunkEmbeddingsIndex{…}, ::Nothing, ::Vector{…}; verbose::Bool, top_k::Int64)
"""
question = """
Implement me a
function find_closest(
        finder::NoSimilarityCheck, emb::AbstractMatrix{<:Real},
        query_emb::AbstractVector{<:Real}, query_tokens::AbstractVector{<:AbstractString} = String[];
        kwargs...)
which just returns all the chunks.
"""
#%%
question = """
I would want to create a code which benchmarks the input token generation speed of models listed in PromptingTools, for example dscode, gpt4t, haiku, claude, gpt4o, gpt4om and also plots them like julia-LLM-Leaderboard plots statistics. 
"""
question = """
I would want a print which prints folders in a tree like structure, the input is a list of filpath strings. Could you use AbstractTrees?
"""
msg = RAG.airag(rag_conf, index; question, retriever_kwargs=kwargs.retriever_kwargs, generator_kwargs=kwargs.generator_kwargs, return_all=true, kwargs...)
PT.pprint(msg)
#%%
f = read("test/benchmark/input_tok.jl", String)
question = """
# Context:
$f

# Query:
I would need to add token count maybe with tiktoken to the input prompt, so I know how much token went into the tests.
"""
msg = RAG.airag(rag_conf, index; question, retriever_kwargs=kwargs.retriever_kwargs, generator_kwargs=kwargs.generator_kwargs, return_all=true, kwargs...)
PT.pprint(msg)
#%%
f = read("test/benchmark/input_tok.jl", String)
question = """
# Context:
$f

# Query:
I need a CustomOpenAISchema which has the ratelimits applied.
struct CustomOpenAISchema <: AbstractOpenAISchema end
"""
msg = RAG.airag(rag_conf, index; question, retriever_kwargs=kwargs.retriever_kwargs, generator_kwargs=kwargs.generator_kwargs, return_all=true, kwargs...)
PT.pprint(msg)
#%%
ai"Are you here?"claudeh
#%%
using EasyContext: get_answer
using PromptingTools: pprint
question = "I need to walk packages. I also want to track whether I could trace in a stack which modules I am in currently."
question = "How to use BM25 for retrieval?"
question = "How do I process the chunks into keywords for BM25?"
# question = "I need to walk packages like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
# question = "I need to walk packages line by line like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
msg = get_answer(question, )
pprint(msg)
#%%
using EasyContext: GLOBAL_INDEX, get_context
ctx = get_context(question, force_rebuild=false)
println.(ctx.sources);
#%%
println.(ctx.context)
#%%
using EasyContext: SimpleContextJoiner
import PromptingTools
const RAG = PromptingTools.Experimental.RAGTools
RAG.build_context!(SimpleContextJoiner(), ctx)
#%%
@show typeof(ctx)
#%%
ctx.filtered_candidates
ctx.reranked_candidates
#%%
using EasyContext: get_relevant_project_files
files = get_relevant_project_files(question, ".")
#%%

result = RAG.retrieve(rag_conf.retriever, index, question; 
return_all=true,
kwargs.retriever_kwargs...
)
#%%
GLOBAL_INDEX[]
#%%
ans.sources
#%%
msg2 = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, return_all=true, kwargs...)
PT.pprint(msg2)