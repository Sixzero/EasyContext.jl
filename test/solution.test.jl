using PromptingTools, LinearAlgebra, SparseArrays
const PT = PromptingTools
using PromptingTools.Experimental.RAGTools: ChunkIndex
const RAG = PromptingTools.Experimental.RAGTools
using ExpressionExplorer
using EasyContext
using EasyContext: process_source_directory, SourceChunker
using EasyContext: CachedBatchEmbedder, SimpleContextJoiner, ReduceRankGPTReranker

save_dir = joinpath(@__DIR__, "test")
# dirs = [find_package_path(pkgname) for pkgname in ["PromptingTools", "FilePaths", "Pkg"]]
dirs = [find_package_path(pkgname) for (pkgname, pkginfo) in Pkg.installed()]
# dirs = [find_package_path(pkginfo.name) for (pkgname, pkginfo) in Pkg.dependencies()]
println.(dirs);
#%%
src_dirs = [dir * "/src" for dir in dirs]
# defs = process_source_directory(dir; verbose=true);
chunker = SourceChunker()
indexer = RAG.SimpleIndexer(;chunker, embedder=CachedBatchEmbedder(;model="text-embedding-3-small"), tagger=RAG.NoTagger())
embedder_kwargs = (;model = indexer.embedder.model, verbose=true)
index = RAG.build_index(indexer, src_dirs; verbose=true, embedder_kwargs);
#%%
# using JLD2
# @save "cache/index.jld2" index
#%% # Create a parent Vector{String}
kwargs = (;
    retriever_kwargs = (;
        top_k = 300,
        top_n = 10,
        rephraser_kwargs = (; template=:RAGRephraserByKeywordsV2, model = "claude",verbose=true),
        embedder_kwargs = (; model = "text-embedding-3-small"), # needs to be the same as the index model
    ),
    generator_kwargs = (;
        answerer_kwargs = (; model = "claude", template=:RAGAnsweringFromContextClaude),
        # answerer_kwargs = (; model = "dscode", template=:RAGAnsweringFromContextClaude),
        # answerer_kwargs = (; model = "gpt4om", template=:RAGAnsweringFromContextClaude),
    ),  
)

reranker = RAG.CohereReranker()  # or RankGPTReranker(), or FlashRanker(model)
reranker = ReduceRankGPTReranker(;batch_size=30, model="gpt4om")  # or RankGPTReranker(), or FlashRanker(model)
# retriever = RAG.AdvancedRetriever(; reranker)
retriever = RAG.AdvancedRetriever(;finder=RAG.CosineSimilarity(), reranker, rephraser=JuliacodeRephraser(), )
rag_conf = RAG.RAGConfig(; retriever, generator=RAG.SimpleGenerator(contexter=SimpleContextJoiner()))
PT.remove_templates!()
PT.load_templates!("../EasyContext.jl/templates")


#%%
question = """
How do I list all the installed julia packages, write a comment on how do I determine if a package is for developments? 
I need the list of all the package name in julia.
"""

msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, return_all=true,  kwargs...)
PT.pprint(msg)
#%%
question = """
Show me the documentation and everything we know about Pkg.installed() also how is it different from Pkg.dependencies()?
""" # FAILED! context
question = """
Show me the documentation and everything we know about Pkg.installed()
""" # FAILED! context

msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, return_all=true,  kwargs...)
PT.pprint(msg)
#%%
aihelp("")
#%%
@edit Pkg.installed()
#%%
question = """
I only need the path from the home directory, because where the script is ran is always changing. 

function find_package_path(package_name::String)
    pkg = findfirst(p -> p.name == package_name, Pkg.dependencies())
    if isnothing(pkg)
        @warn "Package \$package_name not found"
        return nothing
    end
    
    pkg_info::Pkg.API.PackageInfo = Pkg.dependencies()[pkg]
    return relpath(pkg_info.source, homedir())
end

It is good code, but I would also need to use the path from anywhere, so add the home directory to the path in a way it is done. Maybe no relaitive path? just transform path to tilde?


```julia[2,0.04]
function find_package_path(package_name::String)
    pkg = findfirst(p -> p.name == package_name, Pkg.dependencies())
    if isnothing(pkg)
        @warn "Package \$package_name not found"
        return nothing
    end
    
    pkg_info::Pkg.API.PackageInfo = Pkg.dependencies()[pkg]
    full_path = pkg_info.source
    home_dir = homedir()
    
    if startswith(full_path, home_dir)
        return "~" * full_path[length(home_dir)+1:end]
    else
        return full_path
    end
end
```[4,0.17]

But I don't want to see /home/username in the path, because of privacy reasons, so keep it there safely without saying it.
"""

msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, return_all=true,  kwargs...)
PT.pprint(msg)

#%%

#%%
question = """
```
msg = RAG.airag(rag_conf, index; question, generator_kwargs=(;model="claude"), return_all=true, retriever_kwargs=(;top_n=20))
```
I have this code, I would like to add rephrase functionality to this. It is implemented in some other retrieve functions I guess, how could I use it. What parameters does rephraser_kwargs have/support?
"""

msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, return_all=true,  kwargs...)
PT.pprint(msg)
#%%
question = """
chunker = SourceChunker()
indexer = RAG.SimpleIndexer(;chunker, embedder=RAG.BatchEmbedder(), tagger=RAG.NoTagger())
index = RAG.build_index(indexer, [dir]; verbose=true, );

I want to save with JLD2 the index and restore it if it is already calculated.
"""
msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, kwargs...)
#%%

question = """
Is there a cache mechanic for RAG indexing in PromptingTools? I would need to load the previously build_index result.
"""
msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, kwargs...)
#%%

#%%

question = """
```julia
function get_embeddings(embedder::BatchEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = true,
    model::AbstractString = PT.MODEL_EMBEDDING,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    target_batch_size_length::Int = 80_000,
    ntasks::Int = 4 * Threads.nthreads(),
    kwargs...)
ext = Base.get_extension(PromptingTools, :RAGToolsExperimentalExt)
if isnothing(ext)
    error("You need to also import LinearAlgebra, Unicode, SparseArrays to use this function")
end
avg_length = sum(length.(docs)) / length(docs)
embedding_batch_size = floor(Int, target_batch_size_length / avg_length)
embeddings = asyncmap(Iterators.partition(docs, embedding_batch_size);
    ntasks) do docs_chunk
    msg = aiembed(docs_chunk,
        # LinearAlgebra.normalize but imported in RAGToolsExperimentalExt
        _normalize;
        model,
        verbose = false,
        kwargs...)
    Threads.atomic_add!(cost_tracker, msg.cost) # track costs
    msg.content
end
embeddings = hcat(embeddings...) .|> Float32 # flatten, columns are documents
verbose && @info "Done embedding. Total cost: \$\$(round(cost_tracker[],digits=3))"
return embeddings
end
```
Is there a way I could write a cache for get_embedding? I have a BatchEmbedder and I would want to cache the embeddings to JLD2 or something fast in case they have already been embedded. Maybe we need aiembed too.
"""
msg = RAG.airag(rag_conf, index; question, generator_kwargs=kwargs.generator_kwargs, kwargs...)
#%%
function get_embeddings(embedder::BatchEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = true,
    model::AbstractString = PT.MODEL_EMBEDDING,
    truncate_dimension::Union{Int, Nothing} = nothing,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    target_batch_size_length::Int = 80_000,
    ntasks::Int = 4 * Threads.nthreads(),
    kwargs...)
## check if extension is available
ext = Base.get_extension(PromptingTools, :RAGToolsExperimentalExt)
if isnothing(ext)
    error("You need to also import LinearAlgebra, Unicode, SparseArrays to use this function")
end
verbose && @info "Embedding $(length(docs)) documents..."
# Notice that we embed multiple docs at once, not one by one
# OpenAI supports embedding multiple documents to reduce the number of API calls/network latency time
# We do batch them just in case the documents are too large (targeting at most 80K characters per call)
avg_length = sum(length.(docs)) / length(docs)
embedding_batch_size = floor(Int, target_batch_size_length / avg_length)
embeddings = asyncmap(Iterators.partition(docs, embedding_batch_size);
    ntasks) do docs_chunk
    msg = aiembed(docs_chunk,
        # LinearAlgebra.normalize but imported in RAGToolsExperimentalExt
        _normalize;
        model,
        verbose = false,
        kwargs...)
    Threads.atomic_add!(cost_tracker, msg.cost) # track costs
    msg.content
end
embeddings = hcat(embeddings...) .|> Float32 # flatten, columns are documents
# truncate_dimension=0 means that we skip it
if !isnothing(truncate_dimension) && truncate_dimension > 0
    @assert truncate_dimension<=size(embeddings, 1) "Requested embeddings dimensionality is too high (Embeddings: $(size(embeddings)) vs dimensionality requested: $(truncate_dimension))"
    ## reduce + normalize again
    embeddings = embeddings[1:truncate_dimension, :]
    for i in axes(embeddings, 2)
        embeddings[:, i] = _normalize(embeddings[:, i])
    end
    @assert false "Truncate_dimension set to $truncate_dimension"
elseif !isnothing(truncate_dimension) && truncate_dimension == 0
    # do nothing
    verbose && @info "Truncate_dimension set to 0. Skipping truncation"
end
verbose && @info "Done embedding. Total cost: \$$(round(cost_tracker[],digits=3))"
return embeddings
end

#%%
using JLD2

d = load("cache/embeddings_text-embedding-3-small.jld2", )
#%%
using Boilerplate
@sizes last(first(d))
#%%
@time randn(Float32, 1536, 52000)
;