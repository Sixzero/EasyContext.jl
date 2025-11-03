"""
Extract rankings from LLM response content, handling various output formats.
Returns a vector of integers representing document IDs.
Accepted formats:
- "[1, 2, 3]"
- "1,2,3" (optionally space-separated), extra text after the list is ignored.
- Checks both first and last non-empty lines
"""
function extract_ranking(content::AbstractString; verbose::Int=0)::Vector{Int}
    content = strip(content)
    if isempty(content)
        verbose >= 1 && @info "extract_ranking: Empty content"
        return Int[]
    end

    # Get all non-empty lines
    lines = split(content, '\n')
    non_empty_lines = filter(line -> !isempty(strip(line)), lines)
    
    if isempty(non_empty_lines)
        verbose >= 1 && @info "extract_ranking: No non-empty lines found"
        return Int[]
    end

    if length(non_empty_lines) > 1 && verbose >= 2
        @info "extract_ranking: Multiline content, checking first and last lines"
    end

    # Try both first and last non-empty lines
    lines_to_try = length(non_empty_lines) == 1 ? [non_empty_lines[1]] : [non_empty_lines[end], non_empty_lines[1]]
    
    for line in lines_to_try
        line = strip(line)
        result = try_extract_from_line(line; verbose)
        if !isempty(result)
            return result
        end
    end

    # Fallback: unrecognizable format - always warn with full content
    @warn "extract_ranking: Unrecognizable format, full content:\n$(content)"
    return Int[]
end

function try_extract_from_line(line::AbstractString; verbose::Int=0)::Vector{Int}
    # Case 1: Bracket format [1,2,3] or [1]
    if startswith(line, '[')
        local inner        
        if endswith(line, ']')
            inner = line[2:end-1]
        else
            # take until first closing bracket if present
            ci = findfirst(==(']'), line)
            inner = ci === nothing ? line[2:end] : line[2:ci-1]
            verbose >= 1 && @info "extract_ranking: Bracket format without closing bracket: $(repr(line))"
        end
        result = parse_number_sequence(inner; verbose)
        return result
    end

    # Case 2: Starts with a number (comma/space separated); take number-prefix only
    if !isempty(line) && isdigit(line[1])
        number_prefix = take_number_prefix(line)
        result = parse_number_sequence(number_prefix; verbose)
        return result
    end

    return Int[]
end

# Take the leading substring consisting only of digits, commas, or spaces/tabs.
function take_number_prefix(s::AbstractString)::String
    io = IOBuffer()
    for c in s
        if isdigit(c) || c == ',' || c == ' ' || c == '\t'
            write(io, c)
        else
            break
        end
    end
    String(take!(io))
end

"""
Parse a sequence of integers separated by commas and/or spaces/tabs.
- Ignores empty parts
- Keeps order, removes duplicates
"""
function parse_number_sequence(s::AbstractString; verbose::Int=0)::Vector{Int}
    s = strip(s)
    isempty(s) && return Int[]

    out = Int[]
    seen = Set{Int}()
    invalid_parts = String[]
    
    # split on comma or whitespace
    for part in split(s, (',', ' ', '\t'))
        part = strip(part)
        isempty(part) && continue
        
        if !all(isdigit, part)
            push!(invalid_parts, part)
            continue
        end
        
        n = tryparse(Int, part)
        if n === nothing
            push!(invalid_parts, part)
            continue
        end
        
        if !(n in seen)
            push!(out, n)
            push!(seen, n)
        end
    end
    
    if !isempty(invalid_parts) && verbose >= 1
        @info "parse_number_sequence: Skipped invalid parts: $(invalid_parts)"
    end
    
    out
end