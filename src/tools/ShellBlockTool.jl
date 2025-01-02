export truncate_output


@kwdef mutable struct ShellBlockTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    content::String
    run_results::Vector{String} = []
end
ShellBlockTool(cmd::ToolTag) = let (language, content) = parse_code_block(cmd.content); ShellBlockTool(language=language, content=content) end
instantiate(::Val{Symbol(SHELL_BLOCK_TAG)}, cmd::ToolTag) = ShellBlockTool(cmd)
commandname(cmd::Type{ShellBlockTool}) = SHELL_BLOCK_TAG
get_description(cmd::Type{ShellBlockTool}) = """
If you asked to run an sh block. Never do it! You MUSTN'T run any sh block, it will be run by the SYSTEM later! 
You propose the sh script that should be run in a most concise short way and wait for feedback!

Assume all standard tools are available - do not attempt installations.

Format:
Each shell commands which you propose will be found in the corresponing next user message with the format like: 
$(SHELL_BLOCK_TAG)
$(code_format("command", "sh"))

"""
stop_sequence(cmd::Type{ShellBlockTool}) = ""


function execute(cmd::ShellBlockTool; no_confirm=false)
    # !(lowercase(cmd.language) in ["bash", "sh", "zsh"]) && return ""
    print_code(cmd.content)
    
    if no_confirm || get_user_confirmation()
        print_output_header()
        cmd_all_info_stream(`zsh -c $(cmd.content)`)
    else
        "\nOperation cancelled by user."
    end
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