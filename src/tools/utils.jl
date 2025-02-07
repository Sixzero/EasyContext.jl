
function get_user_confirmation()
    print("\e[34mContinue? (y) \e[0m")
    readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0"
end

function print_code(code::AbstractString)
    println("\e[32m$code\e[0m")
end

function print_output_header()
    println("\n\e[36mOutput:\e[0m")
end

function execute_with_output(cmd::Cmd, output=IOBuffer(), error=IOBuffer())
    process = run(pipeline(ignorestatus(cmd), stdout=output, stderr=error))
    return format_cmd_output(output, error, process, debug_msg=cmd)
end

function format_cmd_output(output, error, process; debug_msg=nothing)
    # Try to parse JSON from raw stdout if present
    stdout_str, error_str = strip(String(take!(output))), strip(String(take!(error)))
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
    
    # Return formatted output, only include exit_code if it's non-zero
    parts = String[]
    !isempty(stdout_str) && push!(parts, stdout_str)
    !isempty(error_str) && push!(parts, "stderr=$error_str")
    !isnothing(process) && process.exitcode != 0 && push!(parts, "exit_code=$(process.exitcode)")
    join(parts, "\n")
end
