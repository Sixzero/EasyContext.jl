using PromptingTools
using PromptingTools.Experimental.RAGTools: FileChunker, get_chunks, SimpleIndexer, build_index, CohereReranker, SimpleRetriever, retrieve, RankGPTReranker, NoEmbedder
using AISH: is_project_file
using EasyContext: FullFileChunker, ReduceGPTReranker, CachedBatchEmbedder, NoSimilarityCheck
const RAG = PromptingTools.Experimental.RAGTools

batchsize = 30
chunker = FullFileChunker(max_length=2*128000÷batchsize)

files = String[]
for (root, dir, files_in_dir) in walkdir(".")
  for filepath in files_in_dir
    !is_project_file(filepath) && continue
    push!(files, joinpath(root, filepath))
  end
end
println("Filecount: ", length(files))
chunks, sources = get_chunks(chunker, files)
println("Chunkcount: ", length(chunks))
@show sources
;
#%%
file_indexer = SimpleIndexer(;chunker, embedder=CachedBatchEmbedder(;model="text-embedding-3-large", cache_prefix="files_"))
file_indexer = SimpleIndexer(;chunker, embedder=NoEmbedder())
files_index = build_index(file_indexer, files)

reranker = RAG.CohereReranker()  # or RankGPTReranker(), or FlashRanker(model)
reranker = ReduceGPTReranker(;batch_size=batchsize, model="gpt4om")
# reranker = ReduceGPTReranker(;batch_size=batchsize, model="claudeh")
# reranker = RAG.NoReranker()
retriever = SimpleRetriever(;reranker = CohereReranker())
retriever = SimpleRetriever(;embedder=NoEmbedder(), finder=NoSimilarityCheck(), reranker)
# retriever = RAG.AdvancedRetriever(;reranker, rephraser=JuliacodeRephraser(), )

question = "I need to do a better CacheEmbedder, what change would you do for it? Also where could I write test for it?"
question = "I need a CustomOpenAISchema which has the ratelimits applied.
struct CustomOpenAISchema <: AbstractOpenAISchema end"

result = retrieve(retriever, files_index, question; 
  # kwargs.retriever_kwargs..., 
  top_k = 50,  # This will fetch all chunks
  top_n = 5     # number of final reranked results
)
# result = retrieve(retriever, files_index, question; 
#     kwargs.retriever_kwargs..., 
#     embedder_kwargs=(model = file_indexer.embedder.model,), 
#     top_k=100,  # number of initial candidates
#     top_n=5     # number of final reranked results
# )
#%%
@show result.sources
@show result.reranked_candidates
#%%
indexer.embedder.model
(;kwargs.retriever_kwargs..., embedder_kwargs=(model = indexer.embedder.model,))
kwargs.retriever_kwargs
#%%
using EasyContext: get_relevant_project_files, get_answer
msg = get_answer("I would need to modify the file chunker to a version which walks over a julia project on its include() and includet() graph so it will record what module is he in.")
#%%
msg = get_answer("I would need to modify the file chunker to a version which walks over a julia project on its include() and includet() graph so it will record what module is he in. I think PkgManager has a function similar to what we need here.")
#%%
using PromptingTools
PromptingTools.pprint(msg)
#%%
get_relevant_project_files(message, "."; top_n=10)