using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer
using Pkg
using AISH: get_project_files
using JLD2
using Snowball
import PromptingTools.Experimental.RAGTools as RAG

# Module-level variables to store the RAG configuration and index
const GLOBAL_RAG_CONFIG = Ref{Union{Nothing, Tuple}}(nothing)
const GLOBAL_INDEX = Ref{Union{Nothing, RAG.AbstractChunkIndex}}(nothing)
const GLOBAL_BM25_INDEX = Ref{Union{Nothing, RAG.AbstractChunkIndex}}(nothing)

function select_relevant_files(question::String, file_index; top_k::Int=100, top_n=5, rag_conf=nothing, rephraser_kwargs=nothing)
    if isnothing(rag_conf)
        rag_conf, _ = get_rag_config()
    end
    reranker = ReduceRankGPTReranker(;batch_size=30, model="gpt4om")
    retriever = RAG.SimpleRetriever(;
        finder=RAG.CosineSimilarity(), 
        reranker
    )
    embedder_model, = file_index.extras
    result = RAG.retrieve(retriever, file_index, question; 
        # rephraser_kwargs = (; template=:RAGRephraserByKeywordsV2, model = "claude", verbose =true, ),
        top_k, top_n,
        embedder_kwargs = (; model = embedder_model), 
        return_all=true
    )
    
    
    return result
end

function get_file_index(files::Vector{String}; verbose::Bool=true)
    chunker = FullFileChunker()
    indexer = RAG.SimpleIndexer(;chunker, embedder=CachedBatchEmbedder(;model="text-embedding-3-large"), tagger=RAG.NoTagger())
    RAG.build_index(indexer, files; verbose=verbose, embedder_kwargs=(model=indexer.embedder.model, verbose=verbose), extras=[indexer.embedder.model])
end

function get_relevant_project_files(question::String, project_path::String="."; kwargs...)
  files = get_project_files(project_path)
  get_relevant_files(question, files; kwargs...)
end

function get_relevant_files(question::String, files::Vector{String}; top_k::Int=100, top_n=10, rephraser_kwargs=nothing, verbose::Bool=true, suppress_output::Bool=false)
    file_index = get_file_index(files; verbose=verbose)
    # Select relevant files
    retrieve_result = select_relevant_files(question, file_index; top_k, top_n, rephraser_kwargs)
    
    # Remove linenumbers, and only return the unique filepaths
    relevant_files = unique([split(source, ":")[1] for source in retrieve_result.sources])
    
    if !suppress_output
        # Print the number of relevant files in green
        printstyled("Number of relevant files selected: ", color=:green, bold=true)
        printstyled(length(relevant_files), "\n", color=:green)
        for path in relevant_files
            printstyled("  $path\n", color=:cyan)
        end
    end

    return relevant_files, retrieve_result, file_index
end
function build_installed_package_index(; verbose::Bool=true, force_rebuild::Bool=false)
    CACHE_DIR = let
        dir = joinpath(dirname(@__DIR__), "cache")
        isdir(dir) || mkpath(dir)
        dir
    end
    cache_file = joinpath(CACHE_DIR, "installed_package_index.jld2")
    
    !isnothing(GLOBAL_INDEX[]) && !force_rebuild && return GLOBAL_INDEX[]
    if !force_rebuild && isfile(cache_file)
        return JLD2.load(cache_file, "index")
    end
    
    # Get installed packages
    installed_packages = Pkg.installed()
    
    # Get all dependencies (which include PackageInfo)
    all_dependencies = Pkg.dependencies()
    
    # Filter dependencies to only include installed packages
    pkg_infos = [info for (uuid, info) in all_dependencies if info.name in keys(installed_packages)]
    
    chunker = GolemSourceChunker()
    indexer = RAG.SimpleIndexer(;
        chunker, 
        embedder=CachedBatchEmbedder(;model="text-embedding-3-small"), 
        tagger=RAG.NoTagger()
    )

    index = RAG.build_index(indexer, pkg_infos; verbose, embedder_kwargs=(model=indexer.embedder.model, verbose))
    
    # Save the index to cache
    JLD2.save(cache_file, "index", index)
    
    GLOBAL_INDEX[] = index
end

function get_rag_config(;
    batch_size::Int=50, 
    top_k::Int=300, 
    top_n::Int=10,
    force_rebuild::Bool=false
)

    !isnothing(GLOBAL_RAG_CONFIG[]) && !force_rebuild && return GLOBAL_RAG_CONFIG[]

    # Use a relative path to load the EasyContext templates
    template_path = joinpath(@__DIR__, "..", "templates")
    if !(template_path in PromptingTools.TEMPLATE_PATH)
        PromptingTools.load_templates!(template_path)
    end

    rephraser=JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model = "claude",verbose=true)
    reranker = ReduceRankGPTReranker(;batch_size=batch_size, model="gpt4om")
    retriever = RAG.AdvancedRetriever(;
        finder=RAG.CosineSimilarity(), 
        reranker, 
        rephraser
    )
    
    rag_conf = RAG.RAGConfig(; 
        retriever, 
        generator=RAG.SimpleGenerator(contexter=SimpleContextJoiner())
    )
    
    kwargs = (;
        retriever_kwargs = (;
            top_k, top_n, embedder_kwargs = (; model = "text-embedding-3-small"),
        ),
        generator_kwargs = (;
            answerer_kwargs = (; model = "claude",template=:RAGAnsweringFromContextClaude),
        ),
    )
    
    GLOBAL_RAG_CONFIG[] = (rag_conf, kwargs)
    return rag_conf, kwargs
end

function get_context_embedding(question::String; index=nothing, rag_conf=nothing, force_rebuild=false, suppress_output=false)
    if isnothing(index)
        index = GLOBAL_INDEX[]
        if force_rebuild || isnothing(index)
            index = build_installed_package_index(; force_rebuild)
        end
    end
    
    rephraser = JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model = "claude",verbose=true)
    rephraser = RAG.HyDERephraser()
    rephraser = RAG.NoRephraser()
    reranker = RAG.CohereReranker()
    # reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    retriever = RAG.AdvancedRetriever(;
        finder=RAG.CosineSimilarity(), 
        reranker, 
        rephraser,
    )
    
    result = RAG.retrieve(retriever, index, question; 
        return_all=true,
        embedder_kwargs = (; model = "text-embedding-3-small"),
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), index, result)
    
    if !suppress_output
        # Print the number of context sources in green
        printstyled("Number of context sources: ", color=:green, bold=true)
        printstyled(length(result.sources), "\n", color=:green)
        
        # Print the context sources in a styled manner
        for (index, source) in enumerate(result.sources)
            printstyled("  $source\n", color=:cyan)
        end
    end
    
    return result
end

# New BM25-based get_context function
function get_context_bm25(question::String; index=nothing, force_rebuild=false, suppress_output=false)
    if isnothing(index)
        index = GLOBAL_BM25_INDEX[]
        if force_rebuild || isnothing(index)
            index = build_installed_package_index_bm25(; force_rebuild)
        end
    end
    
    # Create a KeywordsProcessor
    processor = RAG.KeywordsProcessor()

    # Create a BM25Similarity finder
    finder = RAG.BM25Similarity()

    # Create a SimpleBM25Retriever
    retriever = RAG.SimpleBM25Retriever(
        processor=processor,
        finder=finder,
        reranker=RAG.CohereReranker()
    )

    # Perform retrieval
    result = RAG.retrieve(retriever, index, question; 
        return_all=true,
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), index, result)
    
    if !suppress_output
        # Print the number of context sources in green
        printstyled("Number of context sources: ", color=:green, bold=true)
        printstyled(length(result.sources), "\n", color=:green)
        
        # Print the context sources in a styled manner
        for (index, source) in enumerate(result.sources)
            printstyled("  $source\n", color=:cyan)
        end
    end
    
    return result
end

# Update the main get_context function to use BM25 by default
function get_context(question::String; use_bm25::Bool=true, kwargs...)
    if use_bm25
        return get_context_bm25(question; kwargs...)
    else
        return get_context_embedding(question; kwargs...)
    end
end

# New function to build BM25 index
function build_installed_package_index_bm25(; verbose::Bool=true, force_rebuild::Bool=false)
    CACHE_DIR = let
        dir = joinpath(dirname(@__DIR__), "cache")
        isdir(dir) || mkpath(dir)
        dir
    end
    cache_file = joinpath(CACHE_DIR, "installed_package_index_bm25.jld2")
    
    if !force_rebuild && isfile(cache_file)
        return JLD2.load(cache_file, "index")
    end
    
    # Get installed packages
    installed_packages = Pkg.installed()
    
    # Get all dependencies (which include PackageInfo)
    all_dependencies = Pkg.dependencies()
    
    # Filter dependencies to only include installed packages
    pkg_infos = [info for (uuid, info) in all_dependencies if info.name in keys(installed_packages)]
    
    # Create a KeywordsProcessor
    processor = RAG.KeywordsProcessor()

    # Create a KeywordsIndexer
    indexer = RAG.KeywordsIndexer(
        chunker=GolemSourceChunker(),
        processor=processor
    )

    index = RAG.build_index(indexer, pkg_infos; verbose)
    
    # Save the index to cache
    JLD2.save(cache_file, "index", index)
    
    GLOBAL_BM25_INDEX[] = index
    return index
end


function get_answer(question::String; index=nothing, rag_conf=nothing, force_rebuild=false)
    if isnothing(index)
        index = GLOBAL_INDEX[]
        if force_rebuild || isnothing(index)
            index = build_installed_package_index(; force_rebuild)
        end
    end
    
    if isnothing(rag_conf)
        rag_conf, rag_kwargs = get_rag_config()
    end
    
    msg = RAG.airag(rag_conf, index; 
        question, 
        return_all=true, 
        rag_kwargs...
    )
    
    return msg
end

export build_package_index, get_rag_config, get_context, get_answer, get_relevant_project_files, get_file_index

