abstract type AbstractChunk end

# TODO maybe rename to FilePath ?
@kwdef mutable struct SourcePath
  path::AbstractString
  from_line::Union{Int,Nothing} = nothing
  to_line::Union{Int,Nothing} = nothing
end
Base.string(s::SourcePath) = "$(s.path)"* (isnothing(s.from_line) ? "" : ":$(s.from_line)") * (isnothing(s.to_line) ? "" : "-$(s.to_line)")
@kwdef struct SourceChunk <: AbstractChunk
  source::SourcePath
  content::AbstractString
  containing_module::Union{String,Nothing} = nothing
end
# TODO rethink the format.
Base.string(s::SourceChunk) = "# $(string(s.source))"* (isnothing(s.containing_module) ? "" : " $(s.containing_module)") * "\n$(s.content)"


@kwdef struct FileChunk <: AbstractChunk
  source::SourcePath
  content::AbstractString=""
end
Base.string(s::FileChunk) = "# $(string(s.source))\n$(s.content)"

get_source(chunk::String) = chunk
get_source(chunk::AbstractChunk) = get_source(chunk.source)
get_source(s::SourcePath) = string(s)

get_content(chunk::String) = chunk
get_content(chunk::AbstractChunk) = chunk.content
need_source_reparse(chunk::FileChunk) = true 
need_source_reparse(chunk::SourceChunk) = false
need_source_reparse(chunk::String) = false

# TODO maybe we could use such thing? or even better, we could also store a file's age and just use that whether it has changed or not and only return with the new chunk if it has changed otherwise nothing? also naming could be adjusted to be more consistent
function did_chunk_change(chunk::FileChunk, old_chunk::FileChunk)
  content = get_updated_file_content(chunk.source)
  # TODO ...
end
reparse_chunk(chunk::FileChunk) = FileChunk(chunk.source, get_updated_file_content(chunk.source))
function get_updated_file_content(source::SourcePath)
    file_path, from, to = source.path, source.from_line, source.to_line
    !isfile(file_path) && (@warn "File not found: $file_path (pwd: $(pwd()))"; return "")
    chunks_dict = read(file_path, String)
    isnothing(from) && return chunks_dict
    lines = split(chunks_dict, '\n')
    return join(lines[from:min(to, length(lines))], '\n')
end
Base.:(==)(a::FileChunk, b::FileChunk) = a.source == b.source && a.content == b.content