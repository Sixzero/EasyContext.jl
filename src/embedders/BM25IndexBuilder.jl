using PromptingTools.Experimental.RAGTools
import PromptingTools.Experimental.RAGTools as RAG
using JLD2, SHA

@kwdef mutable struct BM25IndexBuilder <: AbstractIndexBuilder
    processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
end

function get_index(builder::BM25IndexBuilder, ctx::OrderedDict{String, String}; cost_tracker = Threads.Atomic{Float64}(0.0), verbose=false)
    chunks, sources = collect(values(ctx)), collect(keys(ctx))
    processor = builder.processor
    
    dtm = RAG.get_keywords(processor, chunks;
        verbose = verbose,
        cost_tracker)

    verbose && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"
    
    index_id = gensym("ChunkKeywordsIndex")
    return RAG.ChunkKeywordsIndex(; id = index_id, chunkdata = dtm, chunks, sources)
end

function (builder::BM25IndexBuilder)(result::RAGContext, args...)
    index = get_index(builder, result)
    finder = RAG.BM25Similarity()
    retriever = RAG.AdvancedRetriever(
        finder=finder,
        reranker=RAG.NoReranker(),
        rephraser=RAG.NoRephraser(),
    )
    retrieved = RAG.retrieve(retriever, index, result.question; top_k=100, return_all=true)
    
    res = RAGContext(SourceChunk(retrieved.sources, retrieved.context), result.question)
    return res
end

get_processor(builder::BM25IndexBuilder) = builder.processor

function get_finder(builder::BM25IndexBuilder)
    RAG.BM25Similarity()
end

function cache_key(builder::BM25IndexBuilder, args...)
    hash_str = hash("$(args)_$(typeof(builder.processor))")
    return bytes2hex(sha256("BM25IndexBuilder_$hash_str"))
end

function cache_filename(builder::BM25IndexBuilder, key::String)
    return "bm25_index_$key.jld2"
end
