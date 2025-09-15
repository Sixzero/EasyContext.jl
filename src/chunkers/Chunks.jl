using FilePathsBase

abstract type AbstractChunk end

# TODO maybe rename to FilePath ?
mutable struct SourcePath
  path::AbstractString
  from_line::Union{Int,Nothing}
  to_line::Union{Int,Nothing}
  

end
function SourcePath(; path::AbstractString, from_line::Union{Int,Nothing}=nothing, to_line::Union{Int,Nothing}=nothing)
  # Only check if the file exists if the path contains line number indicators
  if occursin(":", path)
    if !startswith(path, "http")
      @warn "Creating SourcePath with non-existent file: $path (pwd: $(pwd()))" stacktrace()
    end
  end
  SourcePath(path, from_line, to_line)
end

Base.string(s::SourcePath) = "$(s.path)"* (isnothing(s.from_line) ? "" : ":$(s.from_line)") * (isnothing(s.to_line) ? "" : "-$(s.to_line)")
@kwdef struct SourceChunk <: AbstractChunk
  source::SourcePath
  content::AbstractString
  containing_module::Union{String,Nothing} = nothing
end
# TODO rethink the format.
Base.string(s::SourceChunk) = "# $(string(s.source))"* (isnothing(s.containing_module) ? "" : " $(s.containing_module)") * "\n$(s.content)"


struct FileChunk <: AbstractChunk
  source::SourcePath
  content::AbstractString
end
function FileChunk(; source::String, content::AbstractString, from_line::Union{Int,Nothing}=nothing, to_line::Union{Int,Nothing}=nothing)
  FileChunk(SourcePath(; path=source, from_line, to_line), content)
end

Base.string(s::FileChunk) = "# $(string(s.source))\n$(s.content)"

# New FunctionResultChunk for dynamic function-based content
struct FunctionResultChunk <: AbstractChunk
  method::Function  # Closure that generates the content
  content::AbstractString  # Last cached result
  source::String  # Unique identifier for this function result
end

function FunctionResultChunk(method::Function, source::String)
  # Initialize with method() result
  FunctionResultChunk(method, string(method()), source)
end

Base.string(s::FunctionResultChunk) = "# $(s.source)\n$(s.content)"

get_source(chunk::String) = chunk
get_source(chunk::AbstractChunk) = get_source(chunk.source)
get_source(chunk::FunctionResultChunk) = chunk.source
get_source(s::SourcePath) = string(s)

get_content(chunk::String) = chunk
get_content(chunk::AbstractChunk) = chunk.content
get_content(chunk::FunctionResultChunk) = chunk.content

need_source_reparse(chunk::FileChunk) = isnothing(chunk.source.from_line) && isnothing(chunk.source.to_line)
need_source_reparse(chunk::SourceChunk) = false
need_source_reparse(chunk::FunctionResultChunk) = true  # Always reparse function results to get fresh data
need_source_reparse(chunk::String) = false

# TODO maybe we could use such thing? or even better, we could also store a file's age and just use that whether it has changed or not and only return with the new chunk if it has changed otherwise nothing? also naming could be adjusted to be more consistent
function did_chunk_change(chunk::FileChunk, old_chunk::FileChunk)
  content = get_updated_file_content(chunk.source)
  # TODO ...
end

reparse_chunk(source::SourcePath) = FileChunk(source, get_updated_file_content(source, ""))
reparse_chunk(chunk::FileChunk) = FileChunk(chunk.source, get_updated_file_content(chunk.source, chunk.content))
reparse_chunk(chunk::FunctionResultChunk) = FunctionResultChunk(chunk.method, string(chunk.method()), chunk.source)

# Shared sliding extractor used by both local and remote sources
function extract_content_with_sliding(content::String, from_line::Union{Int,Nothing}, to_line::Union{Int,Nothing}, previous_content::String="", tolerance::Int=10)
  isnothing(from_line) && return content, from_line, to_line
  lines = split(content, '\n')
  total = length(lines)
  if isempty(previous_content) || isnothing(to_line)
    actual_to = isnothing(to_line) ? total : min(to_line, total)
    return join(lines[from_line:actual_to], '\n'), from_line, actual_to
  end
  prev_lines = split(previous_content, '\n')
  win_len = length(prev_lines)
  for off in -tolerance:tolerance
    s = max(1, from_line + off)
    e = min(total, s + win_len - 1)
    e < s && continue
    test_content = join(lines[s:e], '\n')
    if test_content == previous_content
      return test_content, s, e
    end
  end
  actual_to = isnothing(to_line) ? total : min(to_line, total)
  join(lines[from_line:actual_to], '\n'), from_line, actual_to
end

function get_updated_file_content(source::SourcePath, previous_content="")
  file_path, from, to = source.path, source.from_line, source.to_line
  expanded_path = expanduser(file_path)
  if !isfile(expanded_path)
    @warn "File not found: $file_path (expanded: $expanded_path, pwd: $(pwd()))"
    return previous_content
  end
  content = read(expanded_path, String)
  extracted, new_from, new_to = extract_content_with_sliding(content, from, to, previous_content)
  source.from_line = new_from
  source.to_line = new_to
  extracted
end

# Improve equality comparison for FileChunk to focus on meaningful content
Base.:(==)(a::SourcePath, b::SourcePath) = a.path == b.path && a.from_line == b.from_line && a.to_line == b.to_line
Base.:(==)(a::FileChunk, b::FileChunk) = a.source == b.source && strip(a.content) == strip(b.content)