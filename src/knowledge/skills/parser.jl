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

function extract_commands(new_content::String, stream_parser::StreamParser; instant_return=false, preprocess=(v)->v)
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
            stream_parser.command_tasks[current_cmd.content] = @async_showerr preprocess(current_cmd)
            current_content = String[]
            current_cmd = nothing
            stream_parser.last_processed_index[] = processed_idx
            instant_return && return current_cmd
            
        elseif !isnothing(current_cmd) # Content
            push!(current_content, line)
            
        elseif !startswith(line, '<') # Opening tag
            parts = split(strip(line))
            cmd_name = parts[1][2:end] # remove leading "<"
            if cmd_name ∈ allowed_commands
                args, kwargs = length(parts) > 1 ? parse_arguments(parts[2:end]) : (String[], Dict{String,String}())
                current_cmd = Command(cmd_name, args, kwargs, "")
            end
        end
    end

    !isnothing(current_cmd) && warn("Unclosed tag: $(current_cmd.name)")
    return nothing
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
            if cmd.name in ["CREATE", "SHELL_RUN"]
                cmd.kwargs["result"] = execute(specific_cmd; no_confirm)
            else
                cmd.kwargs["result"] = execute(specific_cmd)
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

