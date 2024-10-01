

const colors = Dict{Symbol, Symbol}(
    :NEW       => :blue,
    :UPDATED   => :yellow,
    :UNCHANGED => :light_black,
    :DELETED   => :red,
)

@kwdef mutable struct ChangeTracker
    changes::OrderedDict{String, Symbol} = OrderedDict{String, Symbol}()
    source_parser::Function = default_source_parser
end

function default_source_parser(source::String, current_content::String)
    updated_content = get_updated_content(source)
    return get_chunk_standard_format(source, updated_content)
end

function (tracker::ChangeTracker)(src_content)
    existing_keys = keys(src_content)
    filter!(pair -> pair.first in existing_keys, tracker.changes)

    for (source, content) in src_content
        if !haskey(tracker.changes, source)
            tracker.changes[source] = :NEW
            continue
        end
        new_content = tracker.source_parser(source, content)
        tracker.changes[source] = content == new_content ? :UNCHANGED : :UPDATED
    end
    print_context_updates(tracker; deleted=[k for k in existing_keys if !(k in keys(tracker.changes))], item_type="sources")
    return tracker, src_content
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
    content = read(file_path, String)
    isnothing(line_range) && return content
    lines = split(content, '\n')
    return join(lines[line_range[1]:min(line_range[2], length(lines))], "\n")
end


to_string(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = begin
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


function print_context_updates(tracker::ChangeTracker; deleted, item_type::String="files")
    printstyled("Number of $item_type selected: ", color=:green, bold=true)
    printstyled(length(tracker.changes), "\n", color=:green)
    
    for (item, s) in tracker.changes
        printstyled("  [$s] $item\n", color=colors[s])
    end
    for item in deleted
        printstyled("  [DELETED] $item\n", color=colors[:DELETED])
    end
end
