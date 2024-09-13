const RAG = PromptingTools.Experimental.RAGTools

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
    embedder = CachedBatchEmbedder(embedder=OpenAIBatchEmbedder(;model="text-embedding-3-large"))
    indexer = RAG.SimpleIndexer(;chunker, embedder, tagger=RAG.NoTagger())
    RAG.build_index(indexer, files; verbose=verbose, embedder_kwargs=(model=embedder.embedder.model, verbose=verbose), extras=[embedder.embedder.model])
end

function get_relevant_project_files(question::String, project_path::String="."; kwargs...)
    files = get_project_files(project_path)
    get_relevant_files(question, files; kwargs...)
end

function get_relevant_files(question::String, files::Vector{String}; top_k::Int=100, top_n::Int=10, rephraser_kwargs=nothing, verbose::Bool=true, suppress_output::Bool=false)
    file_index = get_file_index(files; verbose=verbose)
    # Select relevant files
    retrieve_result = select_relevant_files(question, file_index; top_k, top_n, rephraser_kwargs)
    
    return retrieve_result.context, retrieve_result.sources, file_index
end

