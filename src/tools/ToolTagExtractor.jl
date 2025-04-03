export ToolTagExtractor, extract_tool_calls, get_last_tool_result

#  I think we will need a runner and parser separated...

@kwdef mutable struct ToolTagExtractor <: AbstractExtractor
    # for the extracted tools tags
    tool_tags::Vector{ToolTag}=ToolTag[]
    # for the extracted Tools
    tool_tasks::OrderedDict{UUID, Task} = OrderedDict{UUID, Task}()
    skip_execution::Bool = false
    no_confirm::Bool = false

    # for the stream parsing
    last_processed_index::Ref{Int} = Ref(0)
    full_content::String = ""

    # Direct reference to the original tools
    tools::Vector
end
function tool_value(tool::AbstractTool)
    tool
end
function tool_value(tool::Pair{String, T}) where T <: AbstractTool
    second(tool)
end
tool_value(tg) = tg

function ToolTagExtractor(tools::Vector)
    ToolTagExtractor(tools=tools)
end

# Get single line tags dynamically from tools
function get_single_line_tags(tools::Vector)
    [toolname(T) for T in tools if tool_format(T) == :single_line]
end

# Get multi line tags dynamically from tools
function get_multi_line_tags(tools::Vector)
    [toolname(T) for T in tools if tool_format(T) == :multi_line]
end

# Get tool map dynamically from tools
function get_tool_map(tools::Vector)
    Dict{String, Any}(toolname(T) => T for T in tools)
end

function process_immediate_tool!(line::String, stream_parser::ToolTagExtractor, content::String=""; kwargs=Dict())
    tool_tag = parse_tool(line, content; kwargs)
    push!(stream_parser.tool_tags, tool_tag)
    
    # Get tool map dynamically
    tool_map = get_tool_map(stream_parser.tools)
    
    # Create the tool using the tool_map
    tool_creator = tool_map[tool_tag.name]
    tool = tool_creator(tool_tag)
    stream_parser.tool_tasks[get_id(tool)] = @async_showerr preprocess(tool)
end

function update_processed_index!(stream_parser::ToolTagExtractor, lines, last_saved_i::Int, current_i::Int)
    if last_saved_i < current_i
        previous_lines_length = sum(length.(lines[last_saved_i:current_i-1])) + (current_i - last_saved_i)
        stream_parser.last_processed_index[] += previous_lines_length
    end
end

function extract_tool_calls(new_content::String, stream_parser::ToolTagExtractor, io::IO=stdout; kwargs=Dict(), is_flush::Bool=false)
    stream_parser.full_content *= new_content
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    
    # Get tags dynamically
    single_line_tags = get_single_line_tags(stream_parser.tools)
    multi_line_tags = get_multi_line_tags(stream_parser.tools)
    allowed_tools = union(single_line_tags, multi_line_tags)
    
    i = 1
    last_saved_i = 1
    while i <= length(lines)-1
        line = String(lines[i])
        
        # Handle single-line tools
        if startswith.(line, single_line_tags) |> any
            update_processed_index!(stream_parser, lines, last_saved_i, i)
            stream_parser.last_processed_index[] += length(line) + 1
            process_immediate_tool!(line, stream_parser, ""; kwargs)
            last_saved_i = i + 1
            i += 1
            continue
        elseif startswith.(line, multi_line_tags) |> any
            update_processed_index!(stream_parser, lines, last_saved_i, i)
            if i < length(lines) && startswith(lines[i+1], "```")
                block_end = find_code_block_end(lines, allowed_tools, i+1, is_flush)  # Pass is_flush here
                if !isnothing(block_end)
                    content = join(lines[i+1:block_end], '\n')
                    total_length = length(line) + 1 + length(content) + 1  # +1 for newline after tag
                    stream_parser.last_processed_index[] += total_length
                    process_immediate_tool!(line, stream_parser, content; kwargs)
                    last_saved_i = block_end + 1
                    i = block_end + 1
                    continue
                end
            end
        end
        i += 1
    end
end

function find_code_block_end(lines::Vector{<:AbstractString}, allowed_tools,start_idx::Int=1, is_flush=false)
    nesting_level = 1  # Start at 1 since we're already inside a code block
    is_in_multiline_str = false
    last_block_end = nothing

    for (i, line) in enumerate(lines[start_idx:end]) # no need for strip
        # Check if we hit another tool
        if any(startswith.(line, allowed_tools))
            isnothing(last_block_end) && @warn "No block end found before new tool call. How can this happen?"
            return last_block_end
        end

        # Handle docstring boundaries
        if count("\"\"\"", line) == 1
            is_in_multiline_str = !is_in_multiline_str
            continue
        end

        # Skip processing if we're in a docstring
        if is_in_multiline_str
            continue
        end

        # Check for code block markers
        if startswith(line, "```")
            if startswith(line, "```$(END_OF_CODE_BLOCK)")
                return start_idx + i - 1
            elseif length(line) > 3
                nesting_level += 1
            else
                nesting_level -= 1
                last_block_end = start_idx + i - 1
            end
        end
    end
    
    return is_flush ? last_block_end : nothing
end

execute(t::Task) = begin
    cmd = fetch(t)
    @assert false "This might not be worth running $t \n$cmd"
    isnothing(cmd) ? nothing : execute(convert_tool(cmd))
end

function execute_tools(stream_parser::ToolTagExtractor; no_confirm=false, kwargs...)
    if !stream_parser.skip_execution
        # Execute in order
        for (id, task) in stream_parser.tool_tasks
            tool = fetch(task)
            isnothing(tool) && continue
            execute(tool; no_confirm)
        end
    end
end

function get_tool_results(stream_parser::ToolTagExtractor; filter_tools::Vector{DataType}=DataType[])
	output = String[]
	for (id, task) in stream_parser.tool_tasks
			tool = fetch(task)
            !(isempty(filter_tools) || typeof(tool) in filter_tools) && continue
            push!(output, result2string(tool))
	end
	return join(output, "\n")
end

function are_tools_cancelled(stream_parser::ToolTagExtractor)
    all(is_cancelled, fetch.(values(stream_parser.tool_tasks)))
end