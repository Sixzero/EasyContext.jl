export truncate_output

using ToolCallFormat: @deftool, CodeBlock

const EXECUTION_CANCELLED = "Execution cancelled by user."

#==============================================================================#
# BashTool (ShellBlockTool) - Execute shell commands
#==============================================================================#

@deftool "Execute shell commands. Propose concise sh scripts" (
    content::String = "",           # Parsed command (set from codeblock)
    language::String = "sh",        # Parsed language from codeblock
    root_path::Union{Nothing,String} = nothing,
    run_results::Vector{String} = String[]
) function bash(command::CodeBlock => "Shell commands to execute")
    # Parse language from codeblock
    parsed_lang, parsed_content = parse_code_block(string(command))
    content = parsed_content
    !isempty(parsed_lang) && (language = parsed_lang)

    print_code(content)

    result = if get(kw, :no_confirm, false) || get_user_confirmation()
        print_output_header()
        if isnothing(root_path)
            cmd_all_info_stream(`zsh -c $content`)
        else
            cd(root_path) do
                cmd_all_info_stream(`zsh -c $content`)
            end
        end
    else
        EXECUTION_CANCELLED
    end
    push!(run_results, result)
    result
end

# Backward compatibility alias
const ShellBlockTool = BashTool

# Custom overrides
ToolCallFormat.is_cancelled(cmd::BashTool) = !isempty(cmd.run_results) && cmd.run_results[end] == EXECUTION_CANCELLED

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
    format_cmd_output(output, error, process)
end

function truncate_output(output)
    length(output) > 10000*4 ? output[1:6000*4] * "\n...\n[Output truncated]\n...\n" * output[end-2000*4:end] : output
end

LLM_safetorun(cmd::BashTool) = LLM_safetorun(cmd.content)

function ToolCallFormat.result2string(tool::BashTool)
    tool_result = if isempty(tool.run_results) || isempty(tool.run_results[end])
        "No results"
    else
        result = tool.run_results[end]
        length(result) > 20000 ? result[1:12000] * "\n...\n[Output truncated]\n...\n" * result[end-4000:end] : result
    end
    code = get_shortened_code(tool.content)
"""
$(SHELL_BLOCK_OPEN)
$(code)
$(CODEBLOCK_CLOSE)
$(SHELL_RUN_RESULT)
$(tool_result)
$(CODEBLOCK_CLOSE)"""
end
