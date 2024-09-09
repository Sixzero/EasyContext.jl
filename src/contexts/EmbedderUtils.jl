using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer
using Pkg
using AISH: get_project_files
using JLD2
using Snowball
import PromptingTools.Experimental.RAGTools as RAG


# Module-level constants
const CACHE_DIR = let
    dir = joinpath(dirname(@__DIR__), "cache")
    isdir(dir) || mkpath(dir)
    dir
end

# Abstract types
abstract type AbstractIndexBuilder end

# Struct definitions
@kwdef struct EmbeddingIndexBuilder <: AbstractIndexBuilder
    force_rebuild::Bool = false
    verbose::Bool = true
    chunker::RAG.AbstractChunker = GolemSourceChunker()
    embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(model="text-embedding-3-small")
    tagger::RAG.AbstractTagger = RAG.NoTagger()
end

@kwdef struct BM25IndexBuilder <: AbstractIndexBuilder
    force_rebuild::Bool = false
    verbose::Bool = true
    chunker::RAG.AbstractChunker = GolemSourceChunker()
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
    tagger::RAG.AbstractTagger = RAG.NoTagger()
end

@kwdef struct MultiIndexBuilder <: AbstractIndexBuilder
    builders::Vector{<:AbstractIndexBuilder}=[
        EmbeddingIndexBuilder(),
        BM25IndexBuilder()
    ]
    force_rebuild::Bool = false
    verbose::Bool = true
end

@kwdef mutable struct MultiIndexContext
    index::Union{Nothing, RAG.MultiIndex} = nothing
    index_builder::MultiIndexBuilder = MultiIndexBuilder(
        builders=[
            EmbeddingIndexBuilder(),
            BM25IndexBuilder()
        ]
    )
end

@kwdef struct EmbeddingContextProcessor <: AbstractContextProcessor
    index::Union{Nothing, RAG.AbstractChunkIndex} = nothing
    force_rebuild::Bool = false
    suppress_output::Bool = true
end

@kwdef struct BM25ContextProcessor <: AbstractContextProcessor
    index::Union{Nothing, RAG.AbstractChunkIndex} = nothing
    force_rebuild::Bool = false
    suppress_output::Bool = true
end


# Index building functions
function build_index(builder::EmbeddingIndexBuilder, pkg_infos::Vector{<:Pkg.API.PackageInfo})
    cache_file = joinpath(CACHE_DIR, "installed_package_index.jld2")
    
    if !builder.force_rebuild && isfile(cache_file)
        return JLD2.load(cache_file, "index")
    end
    
    indexer = RAG.SimpleIndexer(;
        chunker = builder.chunker, 
        embedder = builder.embedder, 
        tagger = builder.tagger
    )

    index = RAG.build_index(indexer, pkg_infos; verbose=builder.verbose, embedder_kwargs=(model=indexer.embedder.model, verbose=builder.verbose))
    
    JLD2.save(cache_file, "index", index)
    
    return index
end

function build_index(builder::BM25IndexBuilder, pkg_infos::Vector{<:Pkg.API.PackageInfo})
    cache_file = joinpath(CACHE_DIR, "installed_package_index_bm25.jld2")
    
    if !builder.force_rebuild && isfile(cache_file)
        return JLD2.load(cache_file, "index")
    end
    
    indexer = RAG.KeywordsIndexer(
        chunker = builder.chunker,
        processor = builder.processor,
        tagger = builder.tagger
    )

    index = RAG.build_index(indexer, pkg_infos; verbose=builder.verbose)
    
    JLD2.save(cache_file, "index", index)
    
    return index
end

function build_index(builder::MultiIndexBuilder, pkg_infos::Vector{<:Pkg.API.PackageInfo})
    indices = asyncmap(b -> build_index(b, pkg_infos), builder.builders)
    finders = map(b -> get_finder(b), builder.builders)
    
    multi_index = RAG.MultiIndex(indices)
    
    return multi_index, finders
end

function get_finder(builder::EmbeddingIndexBuilder)
    RAG.CosineSimilarity()
end

function get_finder(builder::BM25IndexBuilder)
    RAG.BM25Similarity()
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

function build_multi_index(; verbose::Bool=true, force_rebuild::Bool=false, use_async::Bool=true)
    builders = [
        EmbeddingIndexBuilder(force_rebuild=force_rebuild, verbose=verbose),
        BM25IndexBuilder(force_rebuild=force_rebuild, verbose=verbose)
    ]
    
    indices = asyncmap(build_index, builders)
    
    multi_index = RAG.MultiIndex(indices)
    
    return multi_index
end

# Context processing functions
function get_context(processor::EmbeddingContextProcessor, question::String)
    if isnothing(processor.index) || processor.force_rebuild
        processor.index = build_index(EmbeddingIndexBuilder(force_rebuild=processor.force_rebuild))
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
    
    result = RAG.retrieve(retriever, processor.index, question; 
        return_all=true,
        embedder_kwargs = (; model = "text-embedding-3-small"),
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), processor.index, result)
    
    !processor.suppress_output && print_context_results(result)
    
    return result
end

function get_context(processor::BM25ContextProcessor, question::String)
    if isnothing(processor.index) || processor.force_rebuild
        processor.index = build_index(BM25IndexBuilder(force_rebuild=processor.force_rebuild))
    end
    
    
    # Create a KeywordsProcessor
    processor = RAG.KeywordsProcessor()

    # Create a BM25Similarity finder
    finder = RAG.BM25Similarity()

    reranker = RAG.CohereReranker()
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    # Create a SimpleBM25Retriever
    retriever = RAG.SimpleBM25Retriever(;processor=processor, finder=finder, reranker)

    result = RAG.retrieve(retriever, processor.index, question; 
        return_all=true,
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), processor.index, result)
    
    !processor.suppress_output && print_context_results(result)
    
    return result
end

function get_context(context::MultiIndexContext, question::String; force_rebuild=false, suppress_output=false)
    if isnothing(context.index) || force_rebuild
        isnothing(context.index) && @warn "MultiIndexContext is index is not initialized. It should be initialized by the appropriate context processor (e.g., JuliaPackageContext or PythonPackageContext)."
	pkg_infos = get_package_infos()
        index, finders = build_index(context.index_builder, pkg_infos)
        context.index = index
    end
    
    # Create a KeywordsProcessor for BM25
    processor = RAG.KeywordsProcessor()

    # Create a MultiFinder
    multi_finder = RAG.MultiFinder([get_finder(b) for b in context.index_builder.builders])

    # Create a reranker (you can choose between CohereReranker or ReduceRankGPTReranker)
    reranker = RAG.CohereReranker()
    # reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")

    # Create a retriever that can handle MultiIndex
    retriever = RAG.AdvancedRetriever(
        processor=processor,
        finder=multi_finder,
        reranker=reranker
    )

    result = RAG.retrieve(retriever, context.index, question; 
        return_all=true,
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), context.index, result)
    
    !suppress_output && print_context_results(result)
    
    return result
end

# Utility functions
function get_package_infos()
    installed_packages = Pkg.installed()
    all_dependencies = Pkg.dependencies()
    [info for (uuid, info) in all_dependencies if info.name in keys(installed_packages)]
end

function print_context_results(result)
    printstyled("Number of context sources: ", color=:green, bold=true)
    printstyled(length(result.sources), "\n", color=:green)
    
    for (index, source) in enumerate(result.sources)
        printstyled("  $source\n", color=:cyan)
    end
end

function get_answer(question::String; 
    index=nothing, 
    force_rebuild=false, 
    model="claude",
    template=:RAGAnsweringFromContextClaude,
    top_k=100,
    top_n=10
)
    result = get_context(question; index, force_rebuild, top_k=top_k, top_n=top_n)
    
    # Create the generator with keyword arguments
    generator = RAG.SimpleGenerator(
        contexter=SimpleContextJoiner(),
        answerer_kwargs=(
            model=model,
            template=template
        )
    )
    
    # Generate the response
    result = RAG.generate!(generator, result.index, result)
    
    return result
end

# Exports
export build_index, build_multi_index, get_context, get_answer

