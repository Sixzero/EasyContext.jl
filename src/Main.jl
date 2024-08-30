using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer
using Pkg

# Module-level variables to store the RAG configuration and index
const GLOBAL_RAG_CONFIG = Ref{Union{Nothing, Tuple}}(nothing)
const GLOBAL_INDEX = Ref{Union{Nothing, Any}}(nothing)

function list_project_files(root_dir::String=".")
    files = String[]
    for (root, _, files_in_dir) in walkdir(root_dir)
        for filepath in files_in_dir
          # is file ends with .jl
          if endswith(filepath, ".jl")
            push!(files, joinpath(root, filepath))
          end
        end
    end
    return files
end

function select_relevant_files(question::String, file_index; top_k::Int=100, top_n=5, rag_conf=nothing, kwargs=nothing)
    if isnothing(rag_conf) || isnothing(kwargs)
        rag_conf, kwargs = get_rag_config()
    end
    
    result = RAG.retrieve(rag_conf.retriever, file_index, question; 
        rephraser_kwargs = (; template=:RAGRephraserByKeywordsV2, model = "claude", verbose=true, ),
        top_k, top_n,
        embedder_kwargs = (; model = "text-embedding-3-large"), 
        return_all=true
    )
    
    # Extract unique file paths from the retrieved chunks
    relevant_files = unique(result.sources)
    
    return relevant_files
end

function get_file_index(files::Vector{String}; verbose::Bool=true)
    chunker = FullFileChunker()
    indexer = RAG.SimpleIndexer(;
        chunker, 
        embedder=CachedBatchEmbedder(;model="text-embedding-3-large"), 
        tagger=RAG.NoTagger()
    )
    RAG.build_index(indexer, files; verbose=verbose, embedder_kwargs=(model=indexer.embedder.model, verbose=verbose))
end

function get_relevant_project_files(question::String, project_path::String="."; kwargs...)
  files = list_project_files(project_path)
  get_relevant_files(question, files; kwargs...)
end

function get_relevant_files(question::String, files::Vector{String}; top_k::Int=100, top_n=5, verbose::Bool=true)
    file_index = get_file_index(files; verbose=verbose)
    # Select relevant files
    relevant_sources = select_relevant_files(question, file_index; top_k=top_k, top_n=top_n)
    
    # Remove linenumbers, and only return the unique filepaths
    relevant_files = unique([split(source, ":")[1] for source in relevant_sources])
    
    # Print the number of relevant files in green
    printstyled("Number of relevant files selected: ", color=:green, bold=true)
    printstyled(length(relevant_files), "\n", color=:green)
    for path in relevant_files
        printstyled("  $path\n", color=:cyan)
    end
    
    return relevant_files, file_index
end
function build_installed_package_index(; verbose::Bool=true, force_rebuild::Bool=false)
    !isnothing(GLOBAL_INDEX[]) && !force_rebuild && return GLOBAL_INDEX[]
    pkgnames = collect(keys(Pkg.installed()))
    # pkgnames = collect(keys(Pkg.dependencies()))

    build_package_index(pkgnames; verbose=verbose, force_rebuild=force_rebuild)
end

function build_package_index(pkgnames::Vector{String}; verbose::Bool=true, force_rebuild::Bool=false)
    !isnothing(GLOBAL_INDEX[]) && !force_rebuild && return GLOBAL_INDEX[]

    dirs = [find_package_path(pkgname) for (pkgname, pkginfo) in Pkg.installed()]
    src_dirs = [dir * "/src" for dir in dirs if !isnothing(dir)]
    
    
    chunker = GolemSourceChunker()
    indexer = RAG.SimpleIndexer(;
        chunker, 
        embedder=CachedBatchEmbedder(;model="text-embedding-3-small"), 
        tagger=RAG.NoTagger()
    )
    
    GLOBAL_INDEX[] = RAG.build_index(indexer, src_dirs; verbose=verbose, embedder_kwargs=(model=indexer.embedder.model, verbose=verbose))
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

function get_context(question::String; index=nothing, rag_conf=nothing, force_rebuild=false)
    if isnothing(index)
        index = GLOBAL_INDEX[]
        if force_rebuild || isnothing(index)
            index = build_installed_package_index(; force_rebuild)
        end
    end
    
    if isnothing(rag_conf) || isnothing(kwargs)
        rag_conf, kwargs = get_rag_config()
    end
    
    result = RAG.retrieve(rag_conf.retriever, index, question; 
        return_all=true,
        kwargs.retriever_kwargs...
    )
    
    RAG.build_context!(rag_conf.generator.contexter, index, result)
    
    # Print the number of context sources in green
    printstyled("Number of context sources: ", color=:green, bold=true)
    printstyled(length(result.sources), "\n", color=:green)
    
    # Print the context sources in a styled manner
    for (index, source) in enumerate(result.sources)
        printstyled("  $source\n", color=:cyan)
    end
    
    return result
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

export build_package_index, get_rag_config, get_context, get_answer, list_project_files, get_relevant_project_files, get_file_index

