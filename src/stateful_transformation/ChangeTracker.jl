

const colors = Dict{Symbol, Symbol}(
    :NEW       => :blue,
    :UPDATED   => :yellow,
    :UNCHANGED => :light_black,
    :DELETED   => :red,
)

@kwdef mutable struct ChangeTracker
    changes::OrderedDict{String, Symbol} = OrderedDict{String, Symbol}()
    content::OrderedDict{String, String} = OrderedDict{String, String}()
    source_parser::Function = default_source_parser
    need_source_reparse::Bool = true
    verbose::Bool = true  # Add this line
end


(tracker!::ChangeTracker)(src_content::Context) = begin
    d = tracker!(src_content.d)
    return src_content
end
function (tracker::ChangeTracker)(src_content::OrderedDict)
    current_keys = keys(src_content)
    deleted_keys = [k for k in keys(tracker.changes) if !(k in current_keys)]
    for k in deleted_keys
        delete!(tracker.changes, k)
        delete!(tracker.content, k)
    end
    
    for (source, _) in tracker.changes # we reset everything to :UNCHANGED
        tracker.changes[source] != :UNCHANGED && (tracker.changes[source] = :UNCHANGED)
    end

    for (source, content) in src_content
        if !haskey(tracker.changes, source)
            tracker.changes[source] = :NEW
            tracker.content[source] = content
            continue
        end
        if tracker.need_source_reparse
            new_content = tracker.source_parser(source, content)
            if tracker.content[source] == new_content
                tracker.changes[source] = :UNCHANGED
            else
                tracker.changes[source] = :UPDATED
                tracker.content[source] = new_content
                src_content[source]     = new_content
            end
        end
    end
    tracker.verbose && print_context_updates(tracker; deleted=deleted_keys, item_type="sources")
    return src_content
end

function parse_source(source::String)
    source_nospace = split(source, ' ')[1]
    parts = split(source_nospace, ':')
    length(parts) == 1 && return parts[1], nothing
    start_line, end_line = parse.(Int, split(parts[2], '-'))
    return parts[1], (start_line, end_line)
end

function get_updated_content(source::String)
    file_path, line_range = parse_source(source)
    !isfile(file_path) && (@warn "File not found: $file_path (pwd: $(pwd()))"; return nothing)
    content = read(file_path, String)
    isnothing(line_range) && return content
    lines = split(content, '\n')
    return join(lines[line_range[1]:min(line_range[2], length(lines))], "\n")
end


to_string(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = to_string(tag, element, scr_state, src_cont.d)
to_string(tag::String, element::String, scr_state::ChangeTracker, src_cont::OrderedDict) = begin
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

format_element(element::String, scr_state::ChangeTracker, src_cont::OrderedDict, state::Symbol) = begin
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
