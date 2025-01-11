export StreamParser, extract_tool_calls, run_stream_parser, get_last_tool_result

#  I think we will need a runner and parser separated...

@kwdef mutable struct StreamParser
    last_processed_index::Ref{Int} = Ref(0)
    tool_tags::Vector{ToolTag}=ToolTag[]
    tool_tasks::OrderedDict{UUID, Task} = OrderedDict{UUID, Task}()
    tool_results::OrderedDict{UUID, String} = OrderedDict{UUID, String}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
    single_line_tags::Vector{String} = String[CLICK_TAG, SENDKEY_TAG, CATFILE_TAG]
    multi_line_tags::Vector{String} = String[MODIFY_FILE_TAG, CREATE_FILE_TAG, SHELL_BLOCK_TAG]
end
function process_immediate_tool!(line::String, stream_parser::StreamParser, content::String=""; kwargs=Dict())
    tool_tag = parse_tool(line, content; kwargs)
    push!(stream_parser.tool_tags, tool_tag)
    tool = convert_tool(tool_tag)
    stream_parser.tool_tasks[tool.id] = @async_showerr preprocess(tool)
end

function update_processed_index!(stream_parser::StreamParser, lines, last_saved_i::Int, current_i::Int)
    if last_saved_i < current_i
        previous_lines_length = sum(length.(lines[last_saved_i:current_i-1])) + (current_i - last_saved_i)
        stream_parser.last_processed_index[] += previous_lines_length
    end
end

function extract_tool_calls(new_content::String, stream_parser::StreamParser; kwargs=Dict(), is_flush::Bool=false)
    stream_parser.full_content *= new_content
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    
    allowed_tools = union(stream_parser.single_line_tags,stream_parser.multi_line_tags)
    i = 1
    last_saved_i = 1
    while i <= length(lines)-1
        line = String(lines[i])
        
        # Handle single-line tools
        if startswith.(line, stream_parser.single_line_tags) |> any
            update_processed_index!(stream_parser, lines, last_saved_i, i)
            stream_parser.last_processed_index[] += length(line) + 1
            process_immediate_tool!(line, stream_parser, ""; kwargs)
            last_saved_i = i + 1
            i += 1
            continue
        elseif startswith.(line, stream_parser.multi_line_tags) |> any
            update_processed_index!(stream_parser, lines, last_saved_i, i)
            if i < length(lines) 
                if startswith(lines[i+1], "```")
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
                else
                    # @warn "No opening ``` tag found for multiline command: $line"
                end
            end
        end
        i += 1
    end
end
execute(t::Task) = begin
    cmd = fetch(t)
    isnothing(cmd) ? nothing : execute(convert_tool(cmd))
end
function reset!(stream_parser::StreamParser)
    stream_parser.last_processed_index[] = 0
    empty!(stream_parser.tool_tags)
    empty!(stream_parser.tool_tasks)
    empty!(stream_parser.tool_results)
    stream_parser.full_content = ""
    return stream_parser
end

execute_single_tool(task::Task, stream_parser::StreamParser, no_confirm::Bool=false) = execute_single_tool(fetch(task), stream_parser, no_confirm)
execute_single_tool(cmd::ModifyFileTool, stream_parser::StreamParser, no_confirm::Bool=false) = execute(cmd)
execute_single_tool(cmd::CreateFileTool, stream_parser::StreamParser, no_confirm::Bool=false) = execute(cmd; no_confirm)
function execute_single_tool(cmd::ShellBlockTool, stream_parser::StreamParser, no_confirm::Bool=false)
    stream_parser.tool_results[cmd.id] = execute(cmd; no_confirm)
    !isempty(stream_parser.tool_results[cmd.id]) && push!(cmd.run_results, stream_parser.tool_results[cmd.id])
end
execute_single_tool(cmd, stream_parser::StreamParser, no_confirm::Bool=false) = execute(cmd; no_confirm)


function execute_tools(stream_parser::StreamParser; no_confirm=false)
    for (id, task) in stream_parser.tool_tasks
        tool = fetch(task)
        isnothing(tool) && continue
        tool.id in keys(stream_parser.tool_results) && continue
        execute_single_tool(tool, stream_parser, no_confirm)
    end
    return stream_parser.tool_results
end

function run_stream_parser(stream_parser::StreamParser; root_path=".", no_confirm=false, async=false)
    if !stream_parser.skip_execution 
        cd(root_path) do 
            execute_tools(stream_parser; no_confirm)
        end
    end
end

function get_last_tool_result(stream_parser::StreamParser, no_confirm::Bool=false)
    tool = fetch(last(stream_parser.tool_tasks).second)
    @assert has_stop_sequence(tool) "Last tool should have a stop sequence or we shouldn't enter here.. i think"
    res = stream_parser.tool_results[tool.id]
    return res == "\nOperation cancelled by user." ? nothing : res
end

shell_ctx_2_string(stream_parser::StreamParser) = begin
	isempty(stream_parser.tool_results) && return ""
	
	output = "Previous tools and their results:\n"
	for (id, task) in stream_parser.tool_tasks
			tool = fetch(task)
			if isa(tool, ShellBlockTool) && !isempty(tool.run_results) && !isempty(tool.run_results[end])  # and if it was noblocking!
					shortened_content = get_shortened_code(tool.content)
					output *= """$(SHELL_BLOCK_OPEN)
					$shortened_content
					$(CODEBLOCK_CLOSE)
					$(SHELL_RUN_RESULT)
					$(tool.run_results[end])
					$(CODEBLOCK_CLOSE)
					"""
			end
	end
	return output
end


function find_code_block_end(lines::Vector{<:AbstractString}, allowed_tools,start_idx::Int=1, is_flush=false)
    nesting_level = 1  # Start at 1 since we're already inside a code block
    is_in_multiline_str = false
    last_block_end = nothing

    for (i, line) in enumerate(lines[start_idx:end]) # no need for strip
        # Check if we hit another tool
        if any(startswith.(line, allowed_tools))
            return isnothing(last_block_end) ? nothing : last_block_end
        end

        # Handle docstring boundaries
        if occursin("\"\"\"", line)
            is_in_multiline_str = !is_in_multiline_str
            continue
        end

        # Skip processing if we're in a docstring
        if is_in_multiline_str
            continue
        end

        # Check for code block markers
        if startswith(line, "```")
            if line == "```$(END_OF_CODE_BLOCK)"
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

function parse_tool(first_line::String, content::String=""; kwargs=Dict())
    tag_end = findfirst(' ', first_line)
    name = String(strip(first_line[1:something(tag_end, length(first_line))]))
    args = isnothing(tag_end) ? "" : String(strip(first_line[tag_end+1:end]))
    ToolTag(name=name, args=args, content=content, kwargs=kwargs)
end
