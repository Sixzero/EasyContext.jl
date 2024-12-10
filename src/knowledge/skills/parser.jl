using ..EasyContext: Command

export StreamParser, extract_commands, run_stream_parser, execute_last_command

#  I think we will need a runner and parser separated...

@kwdef mutable struct StreamParser
    last_processed_index::Ref{Int} = Ref(0)
    command_tasks::OrderedDict{UUID, Task} = OrderedDict{UUID, Task}()
    command_results::OrderedDict{UUID, String} = OrderedDict{UUID, String}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
end
function process_immediate_command!(current_cmd, stream_parser, processed_idx)
    # @show current_cmd
    # @show convert_command(current_cmd)
    cmd = convert_command(current_cmd)
    stream_parser.command_tasks[cmd.id] = @async_showerr preprocess(cmd)
    stream_parser.last_processed_index[] = processed_idx
end

function is_valid_command(line::AbstractString)
    startswith(line, '<') || return false
    cmd_end = findfirst(' ', line)
    cmd_name = line[2:something(cmd_end, length(line))-1] # remove <
    return cmd_name ∈ allowed_commands, cmd_name, isnothing(cmd_end) ? "" : line[cmd_end+1:end]
end

function process_command_opening!(line::AbstractString, root_path::String)
    is_valid, cmd_name, remaining_args = is_valid_command(line)
    !is_valid && return nothing

    cmd = Command(String(cmd_name), "", String(remaining_args), Dict{String,String}("root_path"=>root_path))
    return cmd_name in ["CLICK", "SHELL_RUN", "SENDKEY", "CATFILE"] ? (cmd, true) : (cmd, false)
end

function extract_commands(new_content::String, stream_parser::StreamParser; root_path::String="")
    stream_parser.full_content *= new_content
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    processed_idx = stream_parser.last_processed_index[]
    current_content = String[]
    current_cmd = nothing

    for (i, line) in enumerate(lines)
        i==length(lines) && break
        processed_idx += length(line) + 1  # +1 for newline
        line = rstrip(line)

        if !isnothing(current_cmd)
            if startswith(line, "</" * current_cmd.name) # Closing tag
                current_cmd.content = join(current_content, '\n')
                process_immediate_command!(current_cmd, stream_parser, processed_idx)
                current_content = String[]
                current_cmd = nothing
            elseif startswith(line, '<') # New tag found before closing current
                is_valid, = is_valid_command(line)
                if is_valid && !isempty(current_content)
                    # Find last code block end if exists
                    code_block_end = findlast(l->l=="```", current_content)
                    if !isnothing(code_block_end)
                        current_cmd.content = join(current_content[1:code_block_end], '\n')
                        process_immediate_command!(current_cmd, stream_parser, processed_idx)
                        current_content = current_content[code_block_end+1:end]
                        current_cmd = nothing
                    end
                end
            end

            !isnothing(current_cmd) && push!(current_content, line)

        elseif startswith(line, '<') # Opening tag
            cmd_result = process_command_opening!(line, root_path)
            isnothing(cmd_result) && continue

            current_cmd, immediate = cmd_result
            if immediate
                process_immediate_command!(current_cmd, stream_parser, processed_idx)
                current_cmd = nothing
            end
        end
    end

    return nothing
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
    if isa(cmd, CreateFileCommand)
        res = execute(cmd; no_confirm)
    else
        res = execute(cmd)
    end
    stream_parser.command_results[cmd.id] = res
end

function execute_last_command(stream_parser::StreamParser, no_confirm::Bool=false)
    last_command = last(stream_parser.command_tasks)
    cmd = fetch(last_command.second)
    
    if !has_stop_sequence(cmd)
        @warn "Last command does not have a stop sequence"
        return nothing
    end
    no_confirm = no_confirm || LLM_safetorun(cmd)
    res = execute_single_command(cmd, stream_parser, no_confirm)
    res
end

function execute_commands(stream_parser::StreamParser; no_confirm=false)
    for (id, task) in stream_parser.command_tasks
        cmd = fetch(task)
        has_stop_sequence(cmd) && return nothing
        isnothing(cmd) && continue # TODO it signals error in a task, shouldn't really happen.
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
			if isa(cmd, ShellCommand) && !isempty(cmd.run_results)  # and if it was no blocking!!
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

function find_code_block_end(lines::Vector{String}, start_idx::Int=1)
    nesting_level = 0
    in_docstring = false

    for (i, line) in enumerate(lines[start_idx:end])
        stripped = strip(line)

        # Handle docstring boundaries
        if occursin(r"^\"\"\"", stripped)
            in_docstring = !in_docstring
        end

        # Skip processing inside docstrings unless it's a boundary
        stripped == "\"\"\"" && continue

        if startswith(stripped, "```")
            if !in_docstring && length(stripped) > 3  # Opening with language
                nesting_level += 1
            elseif length(stripped) == 3 || all(isspace, stripped[4:end])  # Closing
                nesting_level -= 1
                nesting_level == 0 && return start_idx + i - 1
            end
        end
    end
    return nothing
end

function flush!(stream_parser::StreamParser)
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    isempty(lines) && return

    processed_idx = stream_parser.last_processed_index[]
    current_content = String[]

    for (i, line) in enumerate(lines)
        processed_idx += length(line) + 1

        if startswith(line, '<')
            cmd_result = process_command_opening!(line, "")
            if !isnothing(cmd_result)
                current_content = String[]
                current_cmd, immediate = cmd_result
                immediate && continue

                # Look for code block in remaining lines
                if i < length(lines)
                    remaining_lines = lines[i+1:end]
                    if !isempty(remaining_lines) && startswith(first(remaining_lines), "```")
                        block_end = find_code_block_end(remaining_lines)
                        if !isnothing(block_end)
                            current_cmd.content = join(remaining_lines[1:block_end], '\n')
                            process_immediate_command!(current_cmd, stream_parser, processed_idx)
                        end
                    end
                end
            end
        end
    end
end
