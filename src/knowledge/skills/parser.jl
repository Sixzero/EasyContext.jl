export StreamParser, extract_commands, run_stream_parser, get_last_command_result

#  I think we will need a runner and parser separated...

@kwdef mutable struct StreamParser
    last_processed_index::Ref{Int} = Ref(0)
    command_tasks::OrderedDict{UUID, Task} = OrderedDict{UUID, Task}()
    command_results::OrderedDict{UUID, String} = OrderedDict{UUID, String}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
end
function process_immediate_command!(line::String, stream_parser::StreamParser, content::String=""; root_path::String="")
    current_cmd = parse_command(line, content, kwargs=Dict("root_path"=>root_path))
    cmd = convert_command(current_cmd)
    stream_parser.command_tasks[cmd.id] = @async_showerr preprocess(cmd)
end

function extract_commands(new_content::String, stream_parser::StreamParser; root_path::String="")
    stream_parser.full_content *= new_content
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    
    i = 1
    while i <= length(lines)-1
        line = String(strip(lines[i]))
        
        # Handle single-line commands
        if startswith.(line, [CLICK_TAG, SENDKEY_TAG, CATFILE_TAG]) |> any
            stream_parser.last_processed_index[] += length(line) + 1
            process_immediate_command!(line, stream_parser, ""; root_path)
            i += 1
            continue
        end
        
        # Handle multiline commands
        if startswith.(line, [MODIFY_FILE_TAG, CREATE_FILE_TAG, SHELL_BLOCK_TAG]) |> any
            if i < length(lines) 
                if startswith(strip(lines[i+1]), "```")
                    block_end = find_code_block_end(lines[i+1:end])
                    if !isnothing(block_end)
                        content = join(lines[i+1:i+block_end], '\n') 
                        total_length = length(line)+1 + length(content)+1 + length(END_OF_BLOCK_TAG) + 1  # +1 for newline after tag
                        stream_parser.last_processed_index[] += total_length
                        process_immediate_command!(line, stream_parser, content; root_path)
                        i += block_end + 2
                        continue
                    end
                else
                    @warn "No opening ``` tag found for multiline command: $line"
                end
            end
        end
        i += 1
    end
end
execute(t::Task) = begin
    cmd = fetch(t)
    isnothing(cmd) ? nothing : execute(convert_command(cmd))
end
function reset!(stream_parser::StreamParser)
    stream_parser.last_processed_index[] = 0
    empty!(stream_parser.command_tasks)
    empty!(stream_parser.command_results)
    stream_parser.full_content = ""
    return stream_parser
end

execute_single_command(task::Task, stream_parser::StreamParser, no_confirm::Bool=false) = execute_single_command(fetch(task), stream_parser, no_confirm)
function execute_single_command(cmd, stream_parser::StreamParser, no_confirm::Bool=false)
    stream_parser.command_results[cmd.id] = isa(cmd, CreateFileCommand) ? execute(cmd; no_confirm) : execute(cmd)
end

function get_last_command_result(stream_parser::StreamParser, no_confirm::Bool=false)
    last_command = last(stream_parser.command_tasks)
    cmd = fetch(last_command.second)
    if !has_stop_sequence(cmd)
        @warn "Last command does not have a stop sequence"
        return nothing
    end
    res= stream_parser.command_results[cmd.id]
    if res =="\nOperation cancelled by user."
        return nothing
    end
    return res
end

function execute_commands(stream_parser::StreamParser; no_confirm=false)
    for (id, task) in stream_parser.command_tasks
        cmd = fetch(task)
        isnothing(cmd) && continue # TODO it signals error in a task, shouldn't really happen.
        cmd.id in keys(stream_parser.command_results) && continue
        execute_single_command(cmd, stream_parser, no_confirm)
    end
    return stream_parser.command_results
end

function run_stream_parser(stream_parser::StreamParser; root_path=".", no_confirm=false, async=false)
    if !stream_parser.skip_execution 
        cd(root_path) do 
            execute_commands(stream_parser; no_confirm)
        end
    end
end

shell_ctx_2_string(stream_parser::StreamParser) = begin
	isempty(stream_parser.command_results) && return ""
	
	output = "Previous command executions and their results:\n"
	for (id, task) in stream_parser.command_tasks
			cmd = fetch(task)
			if isa(cmd, ShellBlockCommand) && !isempty(cmd.run_results)  # and if it was no blocking!!
					shortened_content = get_shortened_code(cmd.run_results[end])
					output *= """
					$(SHELL_BLOCK_OPEN)
					$shortened_content
					$(CODEBLOCK_CLOSE)
					$(SHELL_RUN_RESULT)
					$(cmd.run_results)
					$(CODEBLOCK_CLOSE)
					"""
			end
	end
	return output
end

function find_code_block_end(lines::Vector{<:AbstractString}, start_idx::Int=1)
    nesting_level = 0
    in_docstring = false

    for (i, line) in enumerate(lines[start_idx:end])
        stripped = strip(line)
        
        # Handle docstring boundaries
        if occursin(r"^\"\"\"", stripped)
            in_docstring = !in_docstring
        end
        stripped == "\"\"\"" && continue

        if startswith(stripped, "```") || stripped == END_OF_BLOCK_TAG
            if !in_docstring && length(stripped) > 3 && !endswith(stripped, END_OF_BLOCK_TAG)
                nesting_level += 1
            else
                nesting_level -= 1
                nesting_level == 0 && return start_idx + i - 1
            end
        end
    end
    return nothing
end

function parse_command(first_line::String, content::String=""; kwargs::Dict{String,String})
    tag_end = findfirst(' ', first_line)
    name = String(strip(first_line[1:something(tag_end, length(first_line))]))
    args = isnothing(tag_end) ? "" : String(strip(first_line[tag_end+1:end]))
    CommandTag(name=name, args=args, content=content, kwargs=kwargs)
end
