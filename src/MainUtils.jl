using Pkg
using Base.Threads
# const RAG = PromptingTools.Experimental.RAGTools

function RAG.build_index(
  indexer, files_or_docs::Vector{Pkg.API.PackageInfo};
  verbose::Integer = 1,
  extras::Union{Nothing, AbstractVector} = nothing,
  index_id = gensym("ChunkEmbeddingsIndex"),
  chunker = indexer.chunker,
  chunker_kwargs::NamedTuple = NamedTuple(),
  embedder = indexer.embedder,
  embedder_kwargs::NamedTuple = NamedTuple(),
  tagger = indexer.tagger,
  tagger_kwargs::NamedTuple = NamedTuple(),
  api_kwargs::NamedTuple = NamedTuple(),
  cost_tracker = Threads.Atomic{Float64}(0.0))

  ## Split into chunks
  chunks, sources = RAG.get_chunks(chunker, files_or_docs;
    chunker_kwargs...)

  ## Embed chunks
  embeddings = RAG.get_embeddings(embedder, chunks;
    verbose = (verbose > 1),
    cost_tracker,
    api_kwargs, embedder_kwargs...)

  ## Extract tags
  tags_extracted = RAG.get_tags(tagger, chunks;
    verbose = (verbose > 1),
    cost_tracker,
    api_kwargs, tagger_kwargs...)
  # Build the sparse matrix and the vocabulary
  tags, tags_vocab = RAG.build_tags(tagger, tags_extracted)

  (verbose > 0) && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"

  index = RAG.ChunkEmbeddingsIndex(; id = index_id, embeddings, tags, tags_vocab,
    chunks, sources, extras)
  return index
end

function RAG.build_index(
  indexer::RAG.KeywordsIndexer, files_or_docs::Vector{Pkg.API.PackageInfo};
  verbose::Integer = 1,
  extras::Union{Nothing, AbstractVector} = nothing,
  index_id = gensym("ChunkKeywordsIndex"),
  chunker = indexer.chunker,
  chunker_kwargs::NamedTuple = NamedTuple(),
  processor = indexer.processor,
  processor_kwargs::NamedTuple = NamedTuple(),
  tagger = indexer.tagger,
  tagger_kwargs::NamedTuple = NamedTuple(),
  api_kwargs::NamedTuple = NamedTuple(),
  cost_tracker = Threads.Atomic{Float64}(0.0))

## Split into chunks
chunks, sources = RAG.get_chunks(chunker, files_or_docs;
  chunker_kwargs...)

## Tokenize and DTM
dtm = RAG.get_keywords(processor, chunks;
  verbose = (verbose > 1),
  cost_tracker,
  api_kwargs, processor_kwargs...)

## Extract tags
tags_extracted = RAG.get_tags(tagger, chunks;
  verbose = (verbose > 1),
  cost_tracker,
  api_kwargs, tagger_kwargs...)
# Build the sparse matrix and the vocabulary
tags, tags_vocab = RAG.build_tags(tagger, tags_extracted)

(verbose > 0) && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"

index = RAG.ChunkKeywordsIndex(; id = index_id, chunkdata = dtm, tags, tags_vocab,
  chunks, sources, extras)
return index
end
