using ToolCallFormat: Context as ToolContext
# @deftool imported via ToolInterface.jl

@deftool "Read file content. Supports line ranges: file:10-20, file:10-, file:-20 (tail)" function cat_file(file_path::String; ctx::ToolContext)
    path_str, line_start, line_end = parse_file_range(file_path)
    path = expand_path(path_str, ctx.root_path)
    !isfile(path) && return "cat: $(path): No such file or directory"
    file_format(format_path_str(path_str, line_start, line_end),
                extract_lines(read(path, String), line_start, line_end))
end

LLM_safetorun(::CatFileTool) = true

#==============================================================================#
# Helper functions
#==============================================================================#

"""
Parse file path with optional line range: `file:start-end`, `file:start-`, `file:-N` (tail)
Returns (file_path, line_start, line_end) - negative line_start means tail N lines
"""
function parse_file_range(args::String)
    m = match(r"^(.+?):(-\d+)$", args)
    m !== nothing && return (m[1], parse(Int, m[2]), nothing)

    m = match(r"^(.+?):(\d+)-(\d*)$", args)
    m !== nothing && return (m[1], parse(Int, m[2]), m[3] != "" ? parse(Int, m[3]) : nothing)

    m = match(r"^(.+?):(\d+)$", args)
    if m !== nothing
        line = parse(Int, m[2])
        return (m[1], line, line)
    end
    (args, nothing, nothing)
end

function format_path_str(path::String, line_start, line_end)
    line_start === nothing ? path :
    line_start < 0 ? "$(path):$(line_start)" :
    line_end === nothing ? "$(path):$(line_start)-" : "$(path):$(line_start)-$(line_end)"
end

extract_lines(content::String, ::Nothing, _) = content
function extract_lines(content::String, line_start::Int, line_end)
    lines = split(content, '\n')
    n = length(lines)
    if line_start < 0
        start_idx = max(1, n + line_start + 1)
        return join(lines[start_idx:n], '\n')
    end
    join(lines[clamp(line_start, 1, n):clamp(something(line_end, n), line_start, n)], '\n')
end
