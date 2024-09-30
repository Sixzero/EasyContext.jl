
using DataStructures: OrderedDict

@kwdef mutable struct ChangeTracker
    changes::OrderedDict{String, Symbol} = OrderedDict{String, Symbol}()
end

function (tracker::ChangeTracker)(src_content::Context)
    existing_keys = keys(src_content)
    filter!(pair -> pair.first in existing_keys, tracker.changes)

    for (source, content) in src_content
        if !haskey(tracker.changes, source)
            tracker.changes[source] = :NEW
            continue
        end
        new_content = get_chunk_standard_format(source, get_updated_content(source))
        tracker.changes[source] = content == new_content ? :UNCHANGED : :UPDATED
    end
    print_context_updates(tracker; deleted=[k for k in existing_keys if !(k in keys(tracker.changes))], item_type="sources")
    return tracker, src_content
end

const colors = Dict{Symbol, Symbol}(
    :NEW => :blue,
    :UPDATED => :yellow,
    :UNCHANGED => :light_black,
)

function print_context_updates(tracker::ChangeTracker; deleted, item_type::String="files")
    printstyled("Number of $item_type selected: ", color=:green, bold=true)
    printstyled(length(tracker.changes), "\n", color=:green)
    
    for (item, s) in tracker.changes
        printstyled("  [$s] $item\n", color=colors[s])
    end
    for item in deleted
        printstyled("  [DELETED] $item\n", color=:red)
    end
end

function parse_source(source::String)
    parts = split(source, ':')
    length(parts) == 1 && return parts[1], nothing
    start_line, end_line = parse.(Int, split(parts[2], '-'))
    return parts[1], (start_line, end_line)
end

function get_updated_content(source::String)
    file_path, line_range = parse_source(source)
    !isfile(file_path) && (@warn "File not found: $file_path"; return nothing)
    isnothing(line_range) && return read(file_path, String)
    lines = readlines(file_path)
    @assert join(lines, "\n") == read(file_path,String)
    return join(lines[line_range[1]:min(line_range[2], length(lines))], "\n") # TODO unittest because we cut the last enter somehow!?
end

to_string(tag::String, element::String, cb_ext::CodeBlockExtractor) = to_string(tag::String, element::String, cb_ext.shell_results)
to_string(tag::String, element::String, shell_results::AbstractDict{String, CodeBlock}) = begin
    return isempty(shell_results) ? "" : """
    <$tag>
    $(join(["""<$element shortened>
    $(get_shortened_code(codestr(codeblock)))
    </$element>
    <$(SHELL_RUN_RESULT)>
    $(codeblock.run_results[end])
    </$(SHELL_RUN_RESULT)>
    """ for (code, codeblock) in shell_results], "\n"))
    </$tag>
    """
end

to_string(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = format_tag(tag, element, scr_state, src_cont)
format_tag(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = begin
    output = ""
    new_files = format_element(element, scr_state, src_cont, :NEW)
    if !is_really_empty(new_files)
        output *= """
        <$tag NEW>
        $new_files
        </$tag>
        """
    end
    updated_files = format_element(element, scr_state, src_cont, :UPDATED)
    if !is_really_empty(updated_files)
        output *= """
        <$tag UPDATED>
        $updated_files
        </$tag>
        """
    end
    output
end

format_element(element::String, scr_state::ChangeTracker, src_cont::Context, state::Symbol) = begin
    join(["""
    <$element>
    $content
    </$element>
    """ for (src, content) in src_cont if scr_state.changes[src] == state], '\n')
end
