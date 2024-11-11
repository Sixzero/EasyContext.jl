
using Base.Threads

execute_code_block(cb::CodeBlock; no_confirm=false) = withenv("GTK_PATH" => "") do
  code = codestr(cb)
  if cb.type==:MODIFY || cb.type==:CREATE
    head_lines = cb.type ==:MODIFY ? 1 : 4
    tail_lines = cb.type ==:MODIFY ? 1 : 2
    println("\e[32m$(get_shortened_code(code, head_lines, tail_lines))\e[0m")
    cb.type==:CREATE && ((no_confirm || (print("\e[34mContinue? (y) \e[0m"); !(readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0")))) && return "Operation cancelled by user."
    cb.type==:CREATE && println("\n\e[36mOutput:\e[0m")
    return cmd_all_info_modify(`zsh -c $code`)
  else
    !(lowercase(cb.language) in ["bash", "sh", "zsh"]) && return ""
    println("\e[32m$code\e[0m")
    if no_confirm
      println("\n\e[36mOutput:\e[0m")
      return cmd_all_info_stream(`zsh -c $code`)
    else
      print("\e[34mContinue? (y) \e[0m")
      !(readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0") && return "Operation cancelled by user."
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
    return format_cmd_output(output, error, err, process)
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

function format_cmd_output(output, error, err, process)
    join(["$name=$str" for (name, str) in [
        ("stdout", String(take!(output))),
        ("stderr", String(take!(error))),
        ("exception", err),
        ("exit_code", isnothing(process) ? "" : process.exitcode)
    ] if !isempty(str)], "\n")
end

