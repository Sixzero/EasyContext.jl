export truncate_output


@kwdef mutable struct ShellBlockTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    content::String
    root_path::String
    run_results::Vector{String} = []
end
function ShellBlockTool(cmd::ToolTag)
    language, content = parse_code_block(cmd.content)
    ShellBlockTool(
        language=language, 
        content=content,
        root_path=get(cmd.kwargs, "root_path", "")
    ) 
end
instantiate(::Val{Symbol(SHELL_BLOCK_TAG)}, cmd::ToolTag) = ShellBlockTool(cmd)
toolname(cmd::Type{ShellBlockTool}) = SHELL_BLOCK_TAG
# If you asked to run an sh block. Never do it! You MUSTN'T run any sh block, it will be run by the SYSTEM later! 
# and wait for feedback
get_description(cmd::Type{ShellBlockTool}) = """
ShellBlockTool: 
You propose the sh script that should be run in a most concise short way!
Assume all standard cli tools are available - do not attempt installations.

Format:
$(SHELL_BLOCK_TAG)
$(code_format("command", "sh"))

The results will be found in the next user message. You can ask for immediate feedback with #RUN. 
You always need to close the code block, and only after that you can write #RUN.
"""
stop_sequence(cmd::Type{ShellBlockTool}) = ""

tool_format(::Type{ShellBlockTool}) = :multi_line


function execute(cmd::ShellBlockTool; no_confirm=false)
    # !(lowercase(cmd.language) in ["bash", "sh", "zsh"]) && return ""
    print_code(cmd.content)
    
    result = if no_confirm || get_user_confirmation()
        print_output_header()
        cd(cmd.root_path) do
            cmd_all_info_stream(`zsh -c $(cmd.content)`)
        end
    else
        "\nOperation cancelled by user."
    end
    push!(cmd.run_results, result)
    return result
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
    return format_cmd_output(output, error, process)
end

function truncate_output(output)
    if length(output) > 10000*4
        return output[1:6000*4] * "\n...\n[Output truncated: exceeded token limit]\n...\n" * output[end-2000*4:end]
    end
    output
end

function LLM_safetorun(cmd::ShellBlockTool)
	LLM_safetorun(cmd.content)
end

function result2string(tool::ShellBlockTool)
    tool_result= isempty(tool.run_results) || isempty(tool.run_results[end]) ? "No results" : tool.run_results[end]
    shortened_content = get_shortened_code(tool.content)
    """$(SHELL_BLOCK_OPEN)
    $shortened_content
    $(CODEBLOCK_CLOSE)
    $(SHELL_RUN_RESULT)
    $(tool_result)
    $(CODEBLOCK_CLOSE)"""
end
