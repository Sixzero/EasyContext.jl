using FilePathsBase

abstract type AbstractChunk end

# TODO maybe rename to FilePath ?
mutable struct SourcePath
  path::AbstractString
  from_line::Union{Int,Nothing}
  to_line::Union{Int,Nothing}
  
  function SourcePath(; path::AbstractString, from_line::Union{Int,Nothing}=nothing, to_line::Union{Int,Nothing}=nothing)
    # Only check if the file exists if the path contains line number indicators
    if occursin(":", path)
      if !startswith(path, "http")
        @warn "Creating SourcePath with non-existent file: $path (pwd: $(pwd()))" stacktrace()
      end
    end
    new(path, from_line, to_line)
  end
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
reparse_chunk(chunk::FileChunk) = FileChunk(chunk.source, get_updated_file_content(chunk.source, chunk.content))
function get_updated_file_content(source::SourcePath, safety_content="")
    file_path, from, to = source.path, source.from_line, source.to_line
    # Expand tilde in file path to handle paths starting with ~
    expanded_path = expanduser(file_path)
    
    if !isfile(expanded_path)
        @warn "File not found: $file_path (expanded: $expanded_path, pwd: $(pwd()))"
        return safety_content
    end
    
    chunks_dict = read(expanded_path, String)
    isnothing(from) && return chunks_dict
    lines = split(chunks_dict, '\n')
    return join(lines[from:min(to, length(lines))], '\n')
end

# Improve equality comparison for FileChunk to focus on meaningful content
Base.:(==)(a::SourcePath, b::SourcePath) = a.path == b.path && a.from_line == b.from_line && a.to_line == b.to_line
Base.:(==)(a::FileChunk, b::FileChunk) = a.source == b.source && strip(a.content) == strip(b.content)