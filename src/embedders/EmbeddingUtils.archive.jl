# Archive of old structures and functions

# Old BM25IndexBuilder
@kwdef mutable struct OldBM25IndexBuilder <: AbstractIndexBuilder
  chunker::RAG.AbstractChunker = SourceChunker()
  processor::RAG.AbstractProcessor = RAG.KeywordsProcessor()
  tagger::RAG.AbstractTagger = RAG.NoTagger()
  cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
end

# Old JinaEmbeddingIndexBuilder
@kwdef mutable struct OldJinaEmbeddingIndexBuilder <: AbstractIndexBuilder
  chunker::RAG.AbstractChunker = SourceChunker()
  embedder::RAG.AbstractEmbedder = CachedBatchEmbedder(
      embedder=JinaEmbedder(
          model="jina-embeddings-v2-base-code",
      ),
  )
  tagger::RAG.AbstractTagger = RAG.NoTagger()
  cache::Union{Nothing, RAG.AbstractChunkIndex} = nothing
end

# Archived build_index functions
function build_index(builder::OldBM25IndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
  hash_str = hash("$data")
  cache_file = joinpath(CACHE_DIR, "bm25_index_$(hash_str).jld2")

  if !force_rebuild && !isnothing(builder.cache)
      return builder.cache
  elseif !force_rebuild && isfile(cache_file)
      builder.cache = JLD2.load(cache_file, "index")
      return builder.cache
  end

  indexer = RAG.KeywordsIndexer(
      chunker = builder.chunker,
      processor = builder.processor,
      tagger = builder.tagger
  )

  index = RAG.build_index(indexer, data; verbose=verbose)

  JLD2.save(cache_file, "index", index)
  builder.cache = index

  return index
end

function build_index(builder::OldJinaEmbeddingIndexBuilder, data::Vector{T}; force_rebuild::Bool=false, verbose::Bool=true) where T
  hash_str = hash("$data")
  cache_file = joinpath(CACHE_DIR, "jina_embedding_index_$(hash_str).jld2")

  if !force_rebuild && !isnothing(builder.cache)
      return builder.cache
  elseif !force_rebuild && isfile(cache_file)
      builder.cache = JLD2.load(cache_file, "index")
      return builder.cache
  end

  indexer = RAG.SimpleIndexer(;
      chunker = builder.chunker,
      embedder = builder.embedder,
      tagger = builder.tagger
  )

  index = RAG.build_index(indexer, data; verbose=verbose, embedder_kwargs=(model=get_model_name(indexer.embedder), verbose=verbose))

  JLD2.save(cache_file, "index", index)
  builder.cache = index

  return index
end