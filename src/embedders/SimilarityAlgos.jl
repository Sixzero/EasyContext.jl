using RAGTools

function get_score(
  finder::Val{:CosineSimilarity}, emb::AbstractMatrix{<:Real}, query_emb::AbstractVector{<:Real})
  # emb is an embedding matrix where the first dimension is the embedding dimension
  query_emb' * emb |> vec
end

# TODO add PromptingTools PR to separate get_dtm and get_keywords calculations, since they are composable
function get_keywords_easycontext(
    processor::RAGTools.KeywordsProcessor, docs::Union{AbstractString, AbstractVector{<:AbstractString}};
    stemmer = nothing,
    stopwords::Set{String} = Set(RAGTools.STOPWORDS),
    min_length::Integer = 3
    )
    ## check if extension is available
    ext = Base.get_extension(PromptingTools, :RAGToolsExperimentalExt)
    if isnothing(ext)
        # error("You need to also import LinearAlgebra and SparseArrays to use this function")
    end
    ## Preprocess text into tokens
    stemmer = !isnothing(stemmer) ? stemmer : Snowball.Stemmer("english")
    # Single-threaded as stemmer is not thread-safe
    keywords = RAGTools.preprocess_tokens(docs, stemmer; stopwords, min_length)

    ## Early exit if we only want keywords (search time)
    return keywords
end
function get_dtm_easycontext(
    processor::RAGTools.KeywordsProcessor, docs::AbstractVector{<:AbstractString};
    stemmer = nothing,
    stopwords::Set{String} = Set(RAGTools.STOPWORDS),
    min_length::Integer = 3,
    min_term_freq::Int = 1, max_terms::Int = typemax(Int),
    kwargs...)
    keywords = get_keywords_easycontext(processor, docs; stemmer, stopwords, min_length)
    ## Create DTM
    dtm = RAGTools.document_term_matrix(keywords; min_term_freq, max_terms)

    return dtm
end
