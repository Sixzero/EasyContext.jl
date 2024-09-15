
# Struct definitions
struct SourceChunk
  sources::Vector{String}
  contexts::Vector{String}
end

struct RAGContext
  chunk::SourceChunk
  question::String
end
