using PromptingTools.Experimental.RAGTools
using PromptingTools.Experimental.RAGTools: SimpleIndexer, AbstractReranker
using JLD2

function get_embedding_context(index::RAG.AbstractChunkIndex, question::String)
    rephraser = JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model="claude", verbose=true)
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    retriever = RAG.AdvancedRetriever(;
        finder=RAG.CosineSimilarity(), 
        reranker, 
        rephraser
    )
    
    result = RAG.retrieve(retriever, index, question; 
        return_all=true,
        embedder_kwargs = (; model = "text-embedding-3-small"),
        top_k=100,
        top_n=10,
    )
    
    RAG.build_context!(SimpleContextJoiner(), index, result)
    
    return OrderedDict(zip(result.chunk.sources, result.chunk.contexts))
end

# Context processing functions
function get_context(builder::EmbeddingIndexBuilder, question::String; data::Union{Nothing, Vector{T}}=nothing, force_rebuild::Bool=false, suppress_output::Bool=true) where T
    index = isnothing(data) ? builder.cache : build_index(builder, data; force_rebuild=force_rebuild)

    rephraser = JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model = "claude", verbose=true)
    rephraser = RAG.NoRephraser() # RAG.HyDERephraser()
    # reranker = RAG.CohereReranker()
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
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

    return result
end

function get_context(builder::BM25IndexBuilder, question::String; data::Union{Nothing, Vector{T}}=nothing, force_rebuild::Bool=false, suppress_output::Bool=true) where T
    index = isnothing(data) ? builder.cache : build_index(builder, data; force_rebuild=force_rebuild)

    processor = RAG.KeywordsProcessor()
    finder = RAG.BM25Similarity()
    reranker = RAG.CohereReranker()
    reranker = ReduceRankGPTReranker(;batch_size=50, model="gpt4om")
    # Create a SimpleBM25Retriever
    retriever = RAG.SimpleBM25Retriever(;processor=processor, finder=finder, reranker)

    result = RAG.retrieve(retriever, index, question;
        return_all=true,
        top_k=100,
        top_n=10,
    )

    RAG.build_context!(SimpleContextJoiner(), index, result)

    return result
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

    rephraser = JuliacodeRephraser(;template=:RAGRephraserByKeywordsV2, model = "claude", verbose=true)
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

# Export the necessary functions and types
export get_embedding_context, get_context, get_answer, get_rag_config

