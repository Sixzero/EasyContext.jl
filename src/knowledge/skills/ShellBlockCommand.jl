export truncate_output

const shell_block_skill = """
If you asked to run an sh block. Never do it! You MUSTN'T run any sh block, it will be run by the SYSTEM later! 
You propose the sh script that should be run in a most concise short way and wait for feedback!

Assume all standard tools are available - do not attempt installations.

Format:
Each shell commands which you propose will be found in the corresponing next user message with the format like: 
$(code_format("command", "sh"))
"""

const shellblock_skill = Skill(
    name=SHELL_BLOCK_TAG,
    description=shell_block_skill,
    stop_sequence=""
)

@kwdef mutable struct ShellBlockCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "sh"
    content::String
    run_results::Vector{String} = []
end
has_stop_sequence(cmd::ShellBlockCommand) = false

function ShellBlockCommand(cmd::Command)
    args = strip(cmd.args)
    content = startswith(args, "`") && endswith(args, "`") ? strip(args, '`') : args
    ShellBlockCommand(content=content)
end

function execute(cmd::ShellBlockCommand; no_confirm=false)
    !(lowercase(cmd.language) in ["bash", "sh", "zsh"]) && return ""
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

