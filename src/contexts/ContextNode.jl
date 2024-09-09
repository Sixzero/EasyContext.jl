@kwdef mutable struct ContextNode
    title::String
    tracked_sources::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
    updated_sources::Set{String} = Set{String}()
    new_sources::Set{String} = Set{String}()
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
            if new_context != old_context
                push!(updated_sources, source)
                push!(node.updated_sources, source)
                node.tracked_sources[source] = (node.call_counter, new_context)
            else
                push!(unchanged_sources, source)
            end
        end
    end

    # Process new and explicitly updated sources
    for (source, context) in zip(sources, contexts)
        if !haskey(node.tracked_sources, source)
            push!(new_sources, source)
        elseif node.tracked_sources[source][2] != context
            push!(updated_sources, source)
        else
            push!(unchanged_sources, source)
        end
        node.tracked_sources[source] = (node.call_counter, context)
    end
    node.new_sources = new_sources
    node.updated_sources = updated_sources
    print_context_updates(new_sources, updated_sources, unchanged_sources; item_type="sources")
end

function format_context_node(node::ContextNode)
    new_context = join([ctx for (source, (_, ctx)) in node.tracked_sources if source in node.new_sources], "\n")
    updated_context = join([ctx for (source, (_, ctx)) in node.tracked_sources if source in node.updated_sources], "\n")
    
    new_output = isempty(new_context) ? "" : """
    <$(node.title) NEW>
    $new_context
    </$(node.title) NEW>
    """
    
    updated_output = isempty(updated_context) ? "" : """
    <$(node.title) UPDATED>
    $updated_context
    </$(node.title) UPDATED>
    """
    
    empty!(node.new_sources)
    empty!(node.updated_sources)
    
    return new_output * "\n" * updated_output
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
        line_range = parse.(Int, split(parts[2], '-'))
        start_line, end_line = length(line_range) == 1 ? (line_range[1], line_range[1]) : (line_range[1], line_range[2])
        
        # Read specific lines from the file
        lines = readlines(file_path)
        return join(lines[start_line:end_line], "\n")
    else
        # Read the entire file content
        return read(file_path, String)
    end
end

function AISH.cut_history!(node::ContextNode, keep::Int)
    oldest_kept_call = max(1, node.call_counter - keep)
    filter!(pair -> pair.second[1] >= oldest_kept_call, node.tracked_sources)
    intersect!(node.updated_sources, keys(node.tracked_sources))
end
