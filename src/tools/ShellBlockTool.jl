export truncate_output

import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractTool, description_from_schema

@kwdef mutable struct ShellBlockTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    content::String
    root_path::Union{Nothing, String} = nothing
    run_results::Vector{String} = []
end

function ToolCallFormat.create_tool(::Type{ShellBlockTool}, call::ParsedCall)
    content_pv = get(call.kwargs, "command", nothing)
    raw_content = content_pv !== nothing ? content_pv.value : call.content
    language, content = parse_code_block(raw_content)
    root_path_pv = get(call.kwargs, "root_path", nothing)
    ShellBlockTool(language=language, content=content, root_path=root_path_pv !== nothing ? root_path_pv.value : nothing)
end

ToolCallFormat.toolname(::Type{ShellBlockTool}) = "bash"

const SHELL_SCHEMA = (
    name = "bash",
    description = "Execute shell commands. Propose concise sh scripts",
    params = [(name = "command", type = "codeblock", description = "Shell commands to execute", required = true)]
)

ToolCallFormat.get_tool_schema(::Type{ShellBlockTool}) = SHELL_SCHEMA
ToolCallFormat.get_description(::Type{ShellBlockTool}) = description_from_schema(SHELL_SCHEMA)

const EXECUTION_CANCELLED = "Execution cancelled by user."

function ToolCallFormat.execute(cmd::ShellBlockTool; no_confirm=false, kwargs...)
    print_code(cmd.content)

    result = if no_confirm || get_user_confirmation()
        print_output_header()
        if isnothing(cmd.root_path)
            cmd_all_info_stream(`zsh -c $(cmd.content)`)
        else
            cd(cmd.root_path) do
                cmd_all_info_stream(`zsh -c $(cmd.content)`)
            end
        end
    else
        EXECUTION_CANCELLED
    end
    push!(cmd.run_results, result)
    result
end

function ToolCallFormat.is_cancelled(cmd::ShellBlockTool)
    !isempty(cmd.run_results) && cmd.run_results[end] == EXECUTION_CANCELLED
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
    format_cmd_output(output, error, process)
end

function truncate_output(output)
    length(output) > 10000*4 ? output[1:6000*4] * "\n...\n[Output truncated]\n...\n" * output[end-2000*4:end] : output
end

LLM_safetorun(cmd::ShellBlockTool) = LLM_safetorun(cmd.content)

function ToolCallFormat.result2string(tool::ShellBlockTool)
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
