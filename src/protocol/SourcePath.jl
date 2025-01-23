using FilePathsBase

abstract type AbstractSourcePath end

@kwdef struct LocalSourcePath <: AbstractSourcePath
    path::AbstractPath
    line_range::Union{Nothing,Tuple{Int,Int}} = nothing
end

@kwdef struct RemoteSourcePath <: AbstractSourcePath
    hostname::String
    path::AbstractPath
    line_range::Union{Nothing,Tuple{Int,Int}} = nothing
end

# Parse source strings into appropriate SourcePath types
function parse_source_path(source::String)
    # Parse hostname if present
    hostname = nothing
    if occursin(":", source)
        parts = split(source, ":", limit=2)
        if occursin("/", parts[1])  # hostname:path format
            hostname = parts[1]
            source = parts[2]
        end
    end
    
    # Parse line range if present
    line_range = nothing
    if occursin(":", source)
        path_part, range_part = split(source, ":", limit=2)
        if occursin("-", range_part)
            start_line, end_line = parse.(Int, split(range_part, "-"))
            line_range = (start_line, end_line)
        else
            line = parse(Int, range_part)
            line_range = (line, line)
        end
        source = path_part
    end
    
    # Create appropriate SourcePath type
    path = Path(source)
    if isnothing(hostname)
        LocalSourcePath(path=path, line_range=line_range)
    else
        RemoteSourcePath(hostname=hostname, path=path, line_range=line_range)
    end
end

# String representation
function Base.string(sp::LocalSourcePath)
    isnothing(sp.line_range) && return string(sp.path)
    "$(sp.path):$(sp.line_range[1])-$(sp.line_range[2])"
end

function Base.string(sp::RemoteSourcePath)
    base = "$(sp.hostname):$(sp.path)"
    isnothing(sp.line_range) && return base
    "$(base):$(sp.line_range[1])-$(sp.line_range[2])"
end

# Helper functions
get_content(sp::LocalSourcePath) = read_file_range(string(sp.path), sp.line_range)
get_content(sp::RemoteSourcePath) = get_remote_content(sp.hostname, string(sp.path), sp.line_range)

function read_file_range(path::String, line_range::Union{Nothing,Tuple{Int,Int}})
    content = read(path, String)
    isnothing(line_range) && return content
    
    lines = split(content, '\n')
    start_line, end_line = line_range
    join(lines[start_line:min(end_line, length(lines))], '\n')
end

function get_remote_content(hostname::String, path::String, line_range::Union{Nothing,Tuple{Int,Int}})
    service = get_or_create_remote_service(hostname, dirname(path))
    content = service.cache.files[Path(path)]
    isnothing(line_range) && return content
    
    lines = split(content, '\n')
    start_line, end_line = line_range
    join(lines[start_line:min(end_line, length(lines))], '\n')
end
