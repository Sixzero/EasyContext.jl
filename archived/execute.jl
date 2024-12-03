
using Base.Threads

execute_codeblock(cb::CodeBlock; no_confirm=false) = withenv("GTK_PATH" => "") do
  code = codestr(cb)
  if cb.type==:MODIFY || cb.type==:CREATE
    head_lines = cb.type ==:MODIFY ? 1 : 4
    tail_lines = cb.type ==:MODIFY ? 1 : 2
    shortened_code = startswith(code, "curl") ? "curl diff..." : get_shortened_code(code, head_lines, tail_lines)
    println("\e[32m$(shortened_code)\e[0m")
    if cb.type==:CREATE
      dir = dirname(cb.file_path)
      !isdir(dir) && mkpath(dir)
      (no_confirm || (print("\e[34mContinue? (y) \e[0m"); !(readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0"))) && return "\nOperation cancelled by user."
      println("\n\e[36mOutput:\e[0m") 
    end
    return cmd_all_info_modify(`zsh -c $code`)
  else
    !(lowercase(cb.language) in ["bash", "sh", "zsh"]) && return ""
    println("\e[32m$code\e[0m")
    if no_confirm
      println("\n\e[36mOutput:\e[0m")
      return cmd_all_info_stream(`zsh -c $code`)
    else
      print("\e[34mContinue? (y) \e[0m")
      !(readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0") && return "\nOperation cancelled by user."
      println("\n\e[36mOutput:\e[0m")
      return cmd_all_info_stream(`zsh -c $code`)
    end
  end
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

function cmd_all_info_stream(cmd::Cmd, output=IOBuffer(), error=IOBuffer())
    out_pipe, err_pipe = Pipe(), Pipe()
    process = run(pipeline(ignorestatus(cmd), stdout=out_pipe, stderr=err_pipe), wait=false)
    close(out_pipe.in); close(err_pipe.in)
    
    @async_showerr for line in eachline(out_pipe)
        println(line); flush(stdout)
        write(output, line * "\n")
    end
    @async_showerr for line in eachline(err_pipe)
        println(stderr, line); flush(stderr)
        write(error, line * "\n")
    end
    
    wait(process)
    return format_cmd_output(output, error, "", process)
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
