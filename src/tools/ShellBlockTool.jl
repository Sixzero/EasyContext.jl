export truncate_output

using ToolCallFormat: @deftool, TextBlock

const EXECUTION_CANCELLED = "Execution cancelled by user."

#==============================================================================#
# BashTool - Execute shell commands
#==============================================================================#

@deftool "Execute shell commands. Propose concise sh scripts" (
    content::String = "",           # Parsed command (set from codeblock)
    language::String = "sh",        # Parsed language from codeblock
    root_path::Union{Nothing,String} = nothing,
    no_confirm::Bool = false,
    io::IO = stdout,
    run_results::Vector{String} = String[]
) function bash("Shell commands to execute" => command::TextBlock)
    # Parse language from codeblock
    parsed_lang, parsed_content = parse_code_block(command)
    content = parsed_content
    !isempty(parsed_lang) && (language = parsed_lang)

    print_code(content; io)

    raw_result = if no_confirm || get_user_confirmation()
        print_output_header(; io)
        cmd = Cmd(["zsh", "-c", content])
        if isnothing(root_path)
            cmd_all_info_stream(cmd; io)
        else
            cd(root_path) do
                cmd_all_info_stream(cmd; io)
            end
        end
    else
        EXECUTION_CANCELLED
    end
    push!(run_results, raw_result)

    # Format result for LLM
    tool_result = if isempty(raw_result)
        "No results"
    else
        length(raw_result) > 20000 ? raw_result[1:12000] * "\n...\n[Output truncated]\n...\n" * raw_result[end-4000:end] : raw_result
    end
    code = get_shortened_code(content)
    """
$(SHELL_BLOCK_OPEN)
$(code)
$(CODEBLOCK_CLOSE)
$(SHELL_RUN_RESULT)
$(tool_result)
$(CODEBLOCK_CLOSE)"""
end

# Custom overrides
ToolCallFormat.is_cancelled(cmd::BashTool) = !isempty(cmd.run_results) && cmd.run_results[end] == EXECUTION_CANCELLED

function cmd_all_info_stream(cmd::Cmd, output=IOBuffer(), error=IOBuffer(); io::IO=stdout)
    out_pipe, err_pipe = Pipe(), Pipe()
    process = run(pipeline(ignorestatus(cmd), stdout=out_pipe, stderr=err_pipe), wait=false)
    close(out_pipe.in); close(err_pipe.in)

    t_out = @async_showerr for line in eachline(out_pipe)
        println(io, line); flush(io)
        write(output, line * "\n")
    end
    t_err = @async_showerr for line in eachline(err_pipe)
        println(stderr, line); flush(stderr)
        write(error, line * "\n")
    end

    wait(process)
    wait(t_out); wait(t_err)
    format_cmd_output(output, error, process)
end

function truncate_output(output)
    length(output) > 10000*4 ? output[1:6000*4] * "\n...\n[Output truncated]\n...\n" * output[end-2000*4:end] : output
end

LLM_safetorun(cmd::BashTool) = LLM_safetorun(cmd.content)
