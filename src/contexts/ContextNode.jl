@kwdef mutable struct ContextNode
    title::String = "Docs"
    element::String = "Doc"
    attributes::Dict{String, String} = Dict{String, String}()
    tracked_sources::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
    updated_sources::Vector{String} = String[]
    new_sources::Vector{String} = String[]
end

function add_or_update_source!(node::ContextNode, sources::Vector{String}, contexts::Vector{String})
    @assert length(sources) == length(contexts) "Number of sources and contexts must match"
    
    node.call_counter += 1
    new_sources = String[]
    updated_sources = String[]
    unchanged_sources = String[]

    # Check all existing tracked sources for content changes
    for (source, (_, old_context)) in node.tracked_sources
        if source ∉ sources
            new_context = get_updated_content(source)
            if new_context !== nothing && new_context != old_context
                push!(updated_sources, source)
                push!(node.updated_sources, source)
                node.tracked_sources[source] = (node.call_counter, new_context)
            end
        end
    end

    # Process new and explicitly updated sources
    for (source, context) in zip(sources, contexts)
        if !haskey(node.tracked_sources, source)
            push!(new_sources, source)
            node.tracked_sources[source] = (node.call_counter, context)
        else
            current_content = get_updated_content(source)
            if current_content !== nothing && current_content != context
                push!(updated_sources, source)
                node.tracked_sources[source] = (node.call_counter, current_content)
            else
                push!(unchanged_sources, source)
            end
        end
    end
    node.new_sources = new_sources
    node.updated_sources = updated_sources
    print_context_updates(new_sources, updated_sources, unchanged_sources; item_type="sources")
end

function format_context_node(node::ContextNode)
    new_files = format_files(node, node.new_sources, "NEW")
    updated_files = format_files(node, node.updated_sources, "UPDATED")
    
    output = ""
    if !isempty(new_files)
        output *= """
        <$(node.title) NEW>
        $new_files
        </$(node.title)>
        """
    end
    if !isempty(updated_files)
        output *= """
        <$(node.title) UPDATED>
        $updated_files
        </$(node.title)>
        """
    end
    
    empty!(node.new_sources)
    empty!(node.updated_sources)
    
    return output
end

function format_files(node::ContextNode, sources::Vector{String}, tag::String)
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

function AISH.cut_history!(node::ContextNode, keep::Int)
    oldest_kept_call = max(1, node.call_counter - keep)
    filter!(pair -> pair.second[1] >= oldest_kept_call, node.tracked_sources)
    intersect!(node.updated_sources, keys(node.tracked_sources))
end
