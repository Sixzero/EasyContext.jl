@kwdef mutable struct AgeTracker
    tracked_sources::Dict{String, Int} = Dict{String, Int}()
    call_counter::Int = 0
end

function (tcker::AgeTracker)(result::SourceContent; max_history)
    tcker.call_counter += 1
    add_or_update_source!(tcker, result, max_history)
end

function add_or_update_source!(tcker::AgeTracker, src_content::SourceContent, max_history; verbose=true)
    agefiltered_src_content =SourceContent
    # Process new and explicitly updated sources
    for (source, content) in src_content
        if haskey(tcker.tracked_sources, source) 
            if tcker.call_counter-tcker.tracked_sources<max_history 
                agefiltered_src_content[source] = content
            end
        else
            tcker.tracked_sources[source] = tcker.call_counter
            agefiltered_src_content[source] = content
        end
    end
    verbose && print_context_updates(new_sources, updated_sources, unchanged_sources; item_type="sources")
    agefiltered_src_content
end

function format_context_node(node::AgeTracker)
    new_files     = format_files(node, node.new_sources)
    updated_files = format_files(node, node.updated_sources)
    
    output = ""
    if !is_really_empty(new_files)
        output *= """
        <$(node.tag) NEW>
        $new_files
        </$(node.tag)>
        """
    end
    if !is_really_empty(updated_files)
        output *= """
        <$(node.tag) UPDATED>
        $updated_files
        </$(node.tag)>
        """
    end
    
    empty!(node.new_sources)
    empty!(node.updated_sources)
    
    return output
end

function format_files(node::AgeTracker, sources::Vector{String})
    formatted_files = ""
    for source in sources
        content = node.tracked_sources[source][2]
        formatted_files *= """
        <$(node.element)>
        $content
        </$(node.element)>
        """
    end
    return formatted_files
end

function format_context_node(str::String)
    @info "We got a non context node, but already String, this becomes identity."
    return str
end

function get_updated_content(source::String)
    # Extract file path and line numbers if present
    parts = split(source, ':')
    file_path = parts[1]
    if length(parts) > 1
        numbers = split(split(parts[2], ' ')[1], '-')
        if length(numbers)>1

            line_range = Base.parse.(Int, split(split(parts[2], ' ')[1], '-'))
            start_line, end_line = length(line_range) == 1 ? (line_range[1], line_range[1]) : (line_range[1], line_range[2])
            
            # Read specific lines from the file
            lines = readlines(file_path)
            content = join(lines[start_line:min(end_line, end)], "\n")
        else 
            # @info "No way to parse the source file: $source"
            return nothing
        end
    else
        content = read(file_path, String)
        # Read the entire file content
    end
    return get_chunk_standard_format(source, content)
end


