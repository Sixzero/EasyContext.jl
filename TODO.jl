- Use Jina embedder. 
- get_context should not return the concatenated context, because of unique filtering.

- What if all the Context processors were returning the result, with the result.source and result.context fields.
And we would have a ContextNode, which would do all the tracking of source, it would be responsible to not print duplicates. It could have a title, like "Files" which would in the next I describe what exactly to do. 
, and we would have a layer which would return them in the format instead of ## Files: we would return them in:
if the function would get the title="Files" we would return <Files>
contexts_joined_numbered
</Files>
<Files UPDATED> 
contexts_of_updated_files
</Files UPDATED>
instead of the ## Files thing
So the format would be <\$title>
contextsjoined
</\$title>
and then with the UPDATED added.

- File write and also chat through a file?
- A way for AISH to control which flow it needs for its thinking.

- I would like the get_answer to use get_context, so the airag function should get split up in to part a get_context and the answering part based on get_context.

- I would much better like this if we could do this with @kwdef. Also could you do the same for the get_context_embedding. Also I would guess we could do some kind of simplification for the build_installed_package_index and the _bm25 one. I would prefer if you could print out a little bit more lines on how this idea should look like.

- In case this assertion: Not every index is larger than 1!
 is not true we should retry 2 times also I would say we should print out a warning.

### ###################################
I want aish to process the shell things instantly when they are ready.
I want REPL terminal!

### ###
I would need the ContextNode to also be able to be a functor, which can be called itself, and it should receive the RAG Results thing and work accordingly :) I guess this is the first node, which shouldn't return RAGContext, but the string context.


#%%
fix JuliaPakcages. 
- rerank functors
fix Promptingtools stream
Fix faster async shell process.
create aishREPL
#%%
The error it should be able to handle:
TP.Exceptions.StatusError(429, "/v1/embeddings", HTTP.Messages.Response:
"""
HTTP/1.1 429 Too Many Requests
date: Mon, 23 Sep 2024 13:30:55 GMT
server: uvicorn
Content-Length: 504
content-type: application/json
Via: 1.1 google
Alt-Svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
{"detail":"You have exceeded the Tokens Per Minute (TPM) rate limit of 1000000 tokens per minute. In the past minute before this request, you have used 994127 tokens. This payload has approximately 14745 tokens. To prevent further rate limiting, try exponential backoff or sleeping between requests as described in our documentation at https://docs.voyageai.com/docs/rate-limits. If you would like a higher TPM, please make a request using this form: http://www.voyageai.com/request-rate-limit-increase"}""")
Stacktrace:
  [1] (::HTTP.ConnectionRequest.var"#connections#4"{…})(req::HTTP.Messages.Request; proxy::Nothing, socket_type::Type, socket_type_tls::Nothing, readtimeout::Int64, connect_timeout::Int64, logerrors::Bool, logtag::Nothing, closeimmediately::Bool, kw::@Kwargs{…})
The rate limiter thing should be not a function this way in voyager in multiple threads this will fail, because it will on every thread work separately, we need to be able to handle things in the same memory/lock with a struct, maybe this could be RateLimiterTPM or something like this. These RateLimiters should be possible to be used one after the other, depending what feature we need...
#%%
in the test folder I want you to create a benchmark_create.jl which should be about creating benchmark dataset if given questions like:
question = "How to use BM25 for retrieval?"
question = "How do we add KVCache ephemeral cache for anthropic claude ai request?"
question = "How can we use DiffLib library in julia for reconstructing a 3rd file from 2 file?"
question = "Maybe we coul introduce the Chunk struct which would hold context and source and extra fields?"
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat. Which would basically be the improved_readline for AISH.jl "
And what we need to do is create different tests for different solutions (codebase retrieval so some kind of file based thing, and for PkgsSearches...). 
For example in this case we need to test, what the JuliaPackageSearch returns. We need to create a target label set by using the embedder & BM25 and other things with top_n=1000 and then using Reranker with a model like as for now gpt4om, but later on claude or some really good model. 
In a file I think we should have a list of questions... these files probably going to have different formats... there will be one which will have many question = "query" assignments and some other filler codes, but probably we only need the list of questions from the file. But we might need other formattings too.
Also as a sidenote, probably to estabilish the CodebaseContextV3 best accuracy in relevancy as for target labels we probably need no vecDB thing, only Rerank. Also I think somehow we should be able to handle the current commit hash for the CodebaseContext thing.
#%%
We will need to filter the questions whether it is relevant for testing for the specific task (PkgRetrieval, CodebaseContext stuff or anything else).
#%%
ERROR: MethodError: no method matching find_closest(::PromptingTools.Experimental.RAGTools.CosineSimilarity, ::Matrix{Float32}, ::Float32; top_k::Int64)
Closest candidates are:
  find_closest(::PromptingTools.Experimental.RAGTools.CosineSimilarity, ::AbstractMatrix{<:Real}, ::AbstractVector{<:Real}; ...)
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/retrieval.jl:200
  find_closest(::PromptingTools.Experimental.RAGTools.CosineSimilarity, ::AbstractMatrix{<:Real}, ::AbstractVector{<:Real}, ::AbstractVector{<:AbstractString}; top_k, minimum_similarity, kwargs...)
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/retrieval.jl:200
  find_closest(::PromptingTools.Experimental.RAGTools.AbstractSimilarityFinder, ::AbstractMatrix{<:Real}, ::AbstractVector{<:Real}, ::AbstractVector{<:AbstractString}; kwargs...)
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/retrieval.jl:178
  ...
Stacktrace:
 [1] get_positions_and_scores(finder::PromptingTools.Experimental.RAGTools.CosineSimilarity, builder::EmbeddingIndexBuilder, index::PromptingTools.Experimental.RAGTools.ChunkEmbeddingsIndex{…}, query::String, top_k::Int64)
   @ EasyContext ~/repo/EasyContext.jl/src/embedders/SimpleCombinedIndexBuilder.jl:38
 [2] (::EasyContext.CombinedIndexBuilder)(::RAGContext, ::@NamedTuple{…}, ::Vararg{…})
   @ EasyContext ~/repo/EasyContext.jl/src/embedders/SimpleCombinedIndexBuilder.jl:55
#%%
ERROR: MethodError: no method matching getindex(::PromptingTools.Experimental.RAGTools.ChunkEmbeddingsIndex{…}, ::Vector{…}, ::Symbol)
Closest candidates are:
  getindex(::PromptingTools.Experimental.RAGTools.AbstractChunkIndex, ::PromptingTools.Experimental.RAGTools.CandidateChunks{TP, TD}, ::Symbol; sorted) where {TP<:Integer, TD<:Real}
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/types.jl:846
  getindex(::PromptingTools.Experimental.RAGTools.AbstractChunkIndex, ::PromptingTools.Experimental.RAGTools.MultiCandidateChunks{TP, TD}, ::Symbol; sorted) where {TP<:Integer, TD<:Real}
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/types.jl:902
  getindex(::PromptingTools.Experimental.RAGTools.AbstractDocumentIndex, ::PromptingTools.Experimental.RAGTools.AbstractCandidateChunks, ::Symbol)
   @ PromptingTools ~/repo/PromptingTools.jl/src/Experimental/RAGTools/types.jl:841
  ...
Stacktrace:
 [1] (::EasyContext.CombinedIndexBuilder)(::RAGContext, ::@NamedTuple{…}, ::Vararg{…})
   @ EasyContext ~/repo/EasyContext.jl/src/embedders/SimpleCombinedIndexBuilder.jl:71
 [2] (::Pipe)(input::String, ai_state::@NamedTuple{…}, shell_results::Dict{…})
   @ EasyContext ~/repo/EasyContext.jl/src/AISHExtensionV4.jl:18
#%%
I guess we would still need to add back the printing into change_tracker what was done in print_context_updates function.
