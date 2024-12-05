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
      response = aigenerate(prompt; model=model, api_key=api_key, api_kwargs=(max_tokens=max_tokens, temperature=temperature))
      
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
using EasyContext
using EasyContext: get_answer, get_context, JuliaLoader, format_context_node
using EasyContext: BM25IndexBuilder, EmbeddingIndexBuilder, Pipe
import EasyContext: get_context, RAGContext, ReduceRankGPTReranker
using PromptingTools: pprint
# question = "I need to walk packages. I also want to track whether I could trace in a stack which modules I am in currently."
question = "How to use BM25 for retrieval?"
question = "How do we add KVCache ephemeral cache for anthropic claude ai request?"
question = "How can we use DiffLib library in julia for reconstructing a 3rd file from 2 file?"
question = "Maybe we coul introduce the Chunk struct which would hold context and source and extra fields?"
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat. Which would basically be the improved_readline for AISH.jl "
# question = "How can we use DiffLib module in julia for reconstructing a 3rd file from 2 file?"
# question = "What does DiffLib library/module do?"
# question = "How can we use DiffLib.jl library in julia for reconstructing a 3rd file from 2 file?"
# question = "Could we create a file which would use jina or voyage or some ColBERT type multi vector embedding solution?"
# question = "What is in ChunkEmbeddingIndex the .id is used for?"
# question = "How do I process the chunks into keywords for BM25?"
# question = "I need to walk packages like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
# question = "I need to walk packages line by line like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
# msg = get_context(question, force_rebuild=false)
# msg = get_answer(question, )
# pprint(msg)
aistate_mock = (conversations=[(;messages=String[], rel_project_paths=".")], selected_conv_id=1, )
using EasyContext: create_voyage_embedder, create_combined_index_builder
# ctxer = JuliaLoader() * MultiIndexBuilder(;builders=[BM25IndexBuilder()], top_k=100) * rerank(CohereReranker(), top_n=10) * ContextNode(docs="Functions", doc="Function")
# pipe = Pipe([
#     JuliaLoader(),
#     create_voyage_embedder(),
#     # EmbeddingIndexBuilder(top_k=50),
#     # create_combined_index_builder(),
#     # MultiIndexBuilder(;builders=[
#     #     EmbeddingIndexBuilder(),
#     #     # JinaEmbeddingIndexBuilder(),
#     #     # BM25IndexBuilder(),
#     # ]),
#     ReduceRankGPTReranker(),
#     ContextNode(),
# ])
using EasyContext: QuestionCTX
#     CodebaseContextV3(;project_paths=["."]),
#     # MultiIndexBuilder(;builders=[
#     #     EmbeddingIndexBuilder(top_k=50),
#     #     # JinaEmbeddingIndexBuilder(),
#     #     BM25IndexBuilder(),
#     # ], top_k=100),
#     # EmbeddingIndexBuilder(top_k=50),
#     create_combined_index_builder(),
#     # create_voyage_embedder(),
#     ReduceRankGPTReranker(;batch_size=30, model="gpt4om"),
#     ContextNode(tag="Codebase", element="File"),
# ])
# ctxer = CodebaseContextV2()

# for b in ctxer.index_context.index_builder.builders
#     b.force_rebuild = true
# end
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat.  "
question = "I want to correct the cut_history."
question = "Now I need you to create a julia script which could use ai to generate a new file from the input file path and the corresponding .patch file. probably the original input file path could be deducted from the diff, based on what is in the diff, what file it should modify.
"
question = "Could you please implement me with ReplMaker or ReplMaker.jl an AI chat? The basic point would be what currently the improved_readline gives back in the loop, it should be done by this ReplMaker thing."

question_acc    = QuestionCTX()
ctx_question    = question_acc(question) 
file_chunks     = Workspace(["."])(FullFileChunker())
file_chunks_selected = create_combined_index_builder(top_k=30)(file_chunks, ctx_question)
file_chunks_reranked = ReduceRankGPTReranker(batch_size=30, model="gpt4om")(file_chunks_selected, ctx_question)
@show file_chunks_reranked
# @time msg = get_context(ctxer, question, aistate_mock)
# println(format_context_node(msg))
# println(join(msg.new_sources, '\n'))
# @time msg = get_context_embedding(question; force_rebuild=false)
# pprint(msg)
# @time msg = get_context_bm25(question; force_rebuild=false)
# pprint(msg)
;
#%%
println(msg)
#%%
using EasyContext: JinaEmbedder, get_embeddings
    qqs = [question for i  in 1:4000]
    @show length.(qqs)
    res = get_embeddings(JinaEmbedder(), qqs)

    @sizes res
#%%
using EasyContext: get_finder

map(get_finder, ctxer.index_builder.builders)
#%%
using EasyContext: JuliaLoader, BM25IndexBuilder, build_index, JinaEmbedder, JinaEmbeddingIndexBuilder, EmbeddingIndexBuilder
ctxer = JuliaLoader(;index_builder=JinaEmbeddingIndexBuilder(embedder=JinaEmbedder(
    model="jina-embeddings-v2-base-code",
)))
# ctxer = JuliaLoader(;index_builder=EmbeddingIndexBuilder())
using EasyContext: get_package_infos
pkg_infos = get_package_infos(:installed)
pkg_infos = pkg_infos[1:5]
index = build_index(ctxer.index_builder, pkg_infos, force_rebuild=true)
#%%
reduce(hcat,[randn(20,2), randn(20,3)])
#%%
using EasyContext: GoogleLoader, get_context, CodebaseContext, JuliaLoader

question = "Could we create a file which would use jina or voyage or some ColBERT type multi vector embedding solution?"
question = "Could we create a file which would use jina or voyage or some ColBERT type embedder for code embedding?"
question = "Hogyan csináljak alkalmazást, miyen nyelven ajánlanéd?"
question = """ERROR: LoadError: MethodError: no method matching lastindex(::Base.KeySet{String, Dict{String, String}})

Closest candidates are:
  lastindex(::Any, ::Any)"""
question = "What packages could I use for BM25 implementation?"

ctxer = CodebaseContext()
ctxer = GoogleLoader()
ctxer = JuliaLoader()
res = get_context(ctxer, question, nothing, nothing)
println(res);
#%%

function highlight_code_blocks(content::String)
  return replace(content, r"```(\w*)\n([\s\S]*?)\n```" => s -> begin
      language = lowercase(isempty(s[1]) ? "" : s[1])
      code = s[2]
      highlighted_code = if language in ["julia", "jl"]
          highlight_julia(code)
      elseif language in ["sh", "bash", "shell"]
          highlight_shell(code)
      else
          code
      end
      "```$language\n$highlighted_code\n```"
  end)
end

function highlight_julia(code::String)
  keywords = ["function", "end", "if", "else", "elseif", "for", "while", "return", "module", "struct", "mutable", "abstract"]
  types = ["String", "Int", "Float64", "Bool", "Array", "Dict", "Tuple"]
  
  lines = split(code, '\n')
  highlighted_lines = String[]
  
  for line in lines
      # Comment highlighting
      line = replace(line, r"#.*$" => s -> "\e[38;5;240m$s\e[0m")
      
      # Keyword highlighting
      for keyword in keywords
          line = replace(line, Regex("\\b$keyword\\b") => s -> "\e[38;5;204m$s\e[0m")
      end
      
      # Type highlighting
      for type in types
          line = replace(line, Regex("\\b$type\\b") => s -> "\e[38;5;81m$s\e[0m")
      end
      
      # String highlighting
      line = replace(line, r"\".*?\"" => s -> "\e[38;5;220m$s\e[0m")
      
      push!(highlighted_lines, line)
  end
  
  join(highlighted_lines, '\n')
end

function highlight_shell(code::String)
  keywords = ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "do", "done", "in"]
  builtins = ["echo", "cd", "pwd", "ls", "grep", "sed", "awk", "cat", "mkdir", "rm", "cp", "mv"]
  
  lines = split(code, '\n')
  highlighted_lines = String[]
  
  for line in lines
      # Comment highlighting
      line = replace(line, r"#.*$" => s -> "\e[38;5;240m$s\e[0m")
      
      # Keyword highlighting
      for keyword in keywords
          line = replace(line, Regex("\\b$keyword\\b") => s -> "\e[38;5;204m$s\e[0m")
      end
      
      # Builtin command highlighting
      for builtin in builtins
          line = replace(line, Regex("\\b$builtin\\b") => s -> "\e[38;5;81m$s\e[0m")
      end
      
      # Variable highlighting
      line = replace(line, r"\$\w+" => s -> "\e[38;5;220m$s\e[0m")
      
      # String highlighting
      line = replace(line, r"\".*?\"" => s -> "\e[38;5;107m$s\e[0m")
      line = replace(line, r"'.*?'" => s -> "\e[38;5;107m$s\e[0m")
      
      push!(highlighted_lines, line)
  end
  
  join(highlighted_lines, '\n')
end
codeblock = """

```sh
meld ./src/process_query.jl <(cat <<'EOF'
// ... existing code ...

function highlight_code_blocks(content::String)
    return replace(content, r"```(\\w*)\\n([\\s\\S]*?)\\n```" => s -> begin
        language = isempty(s[1]) ? "" : s[1]
        code = s[2]
        "```\$language\\n\$code\\n```"
    end)
end

// ... existing code ...
EOF
)
```
"""
highlight_code_blocks(codeblock)

#%%
using PromptingTools
ai"What is the capital of France?"
#%%
installed_packages = Pkg.installed()
keys(installed_packages)
all_dependencies = Pkg.dependencies()

# Filter dependencies to only include installed packages
pkg_infos = [info for (uuid, info) in all_dependencies if info.name in ["DiffLib"]]
#%%
using PromptingTools
const RAG = PromptingTools.Experimental.RAGTools
using EasyContext: SourceChunker, CachedBatchEmbedder
chunker = SourceChunker()
indexer = RAG.SimpleIndexer(;
    chunker, 
    embedder=CachedBatchEmbedder(;model="text-embedding-3-small"), 
    tagger=RAG.NoTagger()
)

index = RAG.build_index(indexer, pkg_infos; embedder_kwargs=(;model=indexer.embedder.model));
#%%
using PromptingTools
const RAG = PromptingTools.Experimental.RAGTools
using EasyContext: SourceChunker, CachedBatchEmbedder
question = "How can we use DiffLib.jl library in julia for reconstructing a 3rd file from 2 file?"
using EasyContext: GLOBAL_INDEX
# index = GLOBAL_INDEX[]
finder = RAG.CosineSimilarity()
embedder = CachedBatchEmbedder(;model="text-embedding-3-small")
embeddings = RAG.get_embeddings(embedder, [question]; embedder_kwargs=(;model="text-embedding-3-small"))

emb_candidates = RAG.find_closest(finder, index, embeddings, [String[]];
    top_k=40, )
# println.(collect(index[emb_candidates, :chunks, sorted = true]))
# println.(collect(index[emb_candidates, :sources, sorted = true]))
reranker = RAG.CohereReranker()
reranked_candidates = RAG.rerank(reranker, index, question, emb_candidates; top_n=10, )
println.(collect(index[reranked_candidates, :sources, sorted = true]))
;
#%%
using PromptingTools
const RAG = PromptingTools.Experimental.RAGTools
using EasyContext: SourceChunker, CachedBatchEmbedder
question = "How can we use DiffLib.jl library in julia for reconstructing a 3rd file from 2 file?"
using EasyContext: GLOBAL_INDEX
index = GLOBAL_INDEX[]

# Change the finder to BM25Similarity
finder = RAG.BM25Similarity()

# Remove the embedder and embeddings-related code
# embedder = CachedBatchEmbedder(;model="text-embedding-3-small")
# embeddings = RAG.get_embeddings(embedder, [question]; embedder_kwargs=(;model="text-embedding-3-small"))

# Use a KeywordsProcessor for BM25
processor = RAG.KeywordsProcessor()
keywords = RAG.get_keywords(processor, question)

# Use find_closest with BM25Similarity and keywords
bm25_candidates = RAG.find_closest(finder, index, keywords, [String[]];
    top_k=40, )

reranker = RAG.CohereReranker()
reranked_candidates = RAG.rerank(reranker, index, question, bm25_candidates; top_n=10, )
println.(collect(index[reranked_candidates, :sources, sorted = true]))
;
#%%
using EasyContext: get_context

get_context()
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