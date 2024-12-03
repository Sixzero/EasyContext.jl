export StreamParser, extract_commands, run_stream_parser

const allowed_commands::Set{String} = Set(["MODIFY", "CREATE", "EXECUTE", "SEARCH", "CLICK", "READFILE", "KEY", "SHELL_RUN"])

@kwdef mutable struct StreamParser
    last_processed_index::Ref{Int} = Ref(0)
    command_tasks::OrderedDict{String, Task} = OrderedDict{String, Task}()
    command_results::OrderedDict{String, Command} = OrderedDict{String, Command}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
end
function extract_commands(new_content::String, stream_parser::StreamParser; instant_return=false, preprocess=(v)->v, root_path::String="")
    stream_parser.full_content *= new_content
    lines = split(stream_parser.full_content[nextind(stream_parser.full_content, stream_parser.last_processed_index[]):end], '\n')
    processed_idx = stream_parser.last_processed_index[]
    current_content = String[]
    current_cmd = nothing

    for (i, line) in enumerate(lines)
        processed_idx += length(line) + 1  # +1 for the newline
        line = rstrip(line)
        
        if !isnothing(current_cmd) && startswith(line, "</" * current_cmd.name) # Closing tag
            current_cmd.content = join(current_content, '\n')
            current_cmd.kwargs["root_path"] = root_path
            stream_parser.command_tasks[current_cmd.content] = @async_showerr preprocess(current_cmd)
            current_content = String[]
            current_cmd = nothing
            stream_parser.last_processed_index[] = processed_idx
            instant_return && return current_cmd
            
        elseif !isnothing(current_cmd) # Content
            push!(current_content, line)
            
        elseif startswith(line, '<') # Opening tag
            cmd_end = findfirst(' ', line)
            cmd_name = line[2:something(cmd_end, length(line))] # remove <
            if cmd_name ∈ allowed_commands
                remaining_args = isnothing(cmd_end) ? "" : line[cmd_end+1:end]
                current_cmd = Command(cmd_name, "", remaining_args, Dict{String,String}())
            end
        end
    end

    # !isnothing(current_cmd) && @warn("Unclosed tag: $(current_cmd.name)")
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

function execute_commands(stream_parser::StreamParser; no_confirm=false)
    for (content, task) in stream_parser.command_tasks
        cmd = fetch(task)
        if !isnothing(cmd)
            stream_parser.command_results[content] = cmd
            specific_cmd = convert_command(cmd)
            if cmd.name in ["SHELL_RUN", "CREATE"]
                res = execute(specific_cmd; no_confirm)
                isa(specific_cmd, ShellCommand) && (specific_cmd.run_results = res)
            else
                execute(specific_cmd)
            end
        else
            @warn "Failed to execute command: $content"
        end
    end
    return stream_parser.command_results
end

run_stream_parser(stream_parser::StreamParser; no_confirm=false, async=false) = !stream_parser.skip_execution ? execute_commands(stream_parser; no_confirm) : OrderedDict{String, Command}()

to_string(command_run_open::String, command_open::String, command_close::String, stream_parser::StreamParser) = to_string(command_run_open, command_open, command_close, stream_parser.command_results)
function to_string(command_run_open::String, command_open::String, command_close::String, command_results::AbstractDict{String, Command})
    isempty(command_results) && return ""
    
    output = "Previous command executions and their results:\n"
    for (content, command) in command_results
        if command.name ∈ ["EXECUTE", "SEARCH", "SHELL_RUN"]  # and if it was no blocking!!
            shortened_content = get_shortened_code(command2cmd(command))
            output *= """
            $(command_open)
            $shortened_content
            $(command_close)
            $(command_run_open)
            $(haskey(command.kwargs, "result") ? command.kwargs["result"] : "Missing output.")
            $(command_close)
            """
        end
    end
    return output
end

