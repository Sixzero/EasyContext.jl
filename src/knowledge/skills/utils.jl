function parse_code_block(content::String)
    lines = split(content, '\n')
    first_line = first(lines)
    
    if startswith(first_line, "```")
        language = length(first_line) > 3 ? first_line[4:end] : "sh"
        content = join(lines[2:end-1], '\n')
        return language, content
    end
    
    return "sh", content
end


function get_user_confirmation()
    print("\e[34mContinue? (y) \e[0m")
    !(readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0")
end

function print_code(code::AbstractString)
    println("\e[32m$code\e[0m")
end

function print_output_header()
    println("\n\e[36mOutput:\e[0m")
end

function cmd_all_info_modify(cmd::Cmd, output=IOBuffer(), error=IOBuffer())
    err, process = "", nothing
    try
        process = run(pipeline(ignorestatus(cmd), stdout=output, stderr=error))
    catch e
        err = "$e"
    end
    return format_cmd_output(output, error, err, process, debug_msg=cmd)
end

function format_cmd_output(output, error, err, process; debug_msg=nothing)
    # Try to parse JSON from raw stdout if present
    stdout_str, error_str = String(take!(output)), String(take!(error))
    if startswith(stdout_str, "{")
        try
            response = JSON3.read(stdout_str)
            if haskey(response, "error")
                @info "Server returned error" response.error
                println(error_str)
                println("The debug msg:")
                println(debug_msg)
            end
        catch e
            @info "Failed to parse JSON response" error=e
        end
    end
    
    # Return formatted output
    join(["$name=$str" for (name, str) in [
        ("stdout", stdout_str),
        ("stderr", error_str),
        ("exception", err),
        ("exit_code", isnothing(process) ? "" : process.exitcode)
    ] if !isempty(str)], "\n")
end
