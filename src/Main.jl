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

function select_relevant_files(question::String, file_index; top_k::Int=100, top_n=5, rephraser_kwargs=nothing)
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

function build_multi_index(; verbose::Bool=true, force_rebuild::Bool=false)
    
    # Build or load embedding-based index
    embedding_index = build_installed_package_index(; verbose, force_rebuild)
    
    # Build or load BM25-based index
    bm25_index = build_installed_package_index_bm25(; verbose, force_rebuild)
    
    # Create MultiIndex
    multi_index = RAG.MultiIndex([embedding_index, bm25_index])
    
    return multi_index
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

struct BM25JuliaPackageContextProcessor <: AbstractContextProcessor
    processor::RAG.KeywordsProcessor
    finder::RAG.BM25Similarity
    reranker::Union{RAG.CohereReranker, ReduceRankGPTReranker}
end

function BM25JuliaPackageContextProcessor(;
    reranker_type::Symbol = :cohere,
    batch_size::Int = 50,
    model::String = "gpt4om"
)
    processor = RAG.KeywordsProcessor()
    finder = RAG.BM25Similarity()
    reranker = if reranker_type == :cohere
        RAG.CohereReranker()
    else
        ReduceRankGPTReranker(; batch_size = batch_size, model = model)
    end
    BM25JuliaPackageContextProcessor(processor, finder, reranker)
end

# New BM25-based get_context function
function get_context(
    context_processor::BM25JuliaPackageContextProcessor,
	question::String; index=nothing, force_rebuild=false, suppress_output=false)
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

    reranker = RAG.CohereReranker()
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    # Create a SimpleBM25Retriever
    retriever = RAG.SimpleBM25Retriever(;processor=processor, finder=finder, reranker)

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

"""
    get_context(question::String; index=nothing, force_rebuild=false, suppress_output=false)

Retrieve context for a given question using a multi-index approach.

# Arguments
- `question::String`: The question to retrieve context for.
- `index=nothing`: An optional pre-built index to use. If not provided, one will be built or loaded.
- `force_rebuild=false`: Whether to force rebuilding the index even if a cached version exists.
- `suppress_output=false`: Whether to suppress printing of retrieval results.

# Returns
The retrieval result containing relevant context.
"""
function get_context(question::String; index=nothing, force_rebuild=false, suppress_output=false)
    if isnothing(index)
        index = build_multi_index(; force_rebuild)
    end
    
    # Create a KeywordsProcessor for BM25
    processor = RAG.KeywordsProcessor()

    # Create finders for both embedding and BM25
    embedding_finder = RAG.CosineSimilarity()
    bm25_finder = RAG.BM25Similarity()

    # Create a MultiFinder
    multi_finder = RAG.MultiFinder([embedding_finder, bm25_finder])

    # Create a reranker (you can choose between CohereReranker or ReduceRankGPTReranker)
    reranker = RAG.CohereReranker()
    # reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")

    # Create a retriever that can handle MultiIndex
    retriever = RAG.AdvancedRetriever(
        processor=processor,
        finder=finder.finder,
        reranker=reranker
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

function get_answer(question::String; index=nothing, rag_conf=nothing, force_rebuild=false)
    if isnothing(rag_conf)
        rag_conf, rag_kwargs = get_rag_config()
    end
    
    # Get context
    result = get_context(question; index, rag_conf, force_rebuild)
    
    # Generate the response
    generator_kwargs = get(rag_kwargs, :generator_kwargs, NamedTuple())
    result = RAG.generate!(rag_conf.generator, result.index, result; 
        generator_kwargs...
    )
    
    return result
end

export build_package_index, get_rag_config, get_context, get_answer, get_relevant_project_files, get_file_index

