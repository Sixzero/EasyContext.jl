const SHELL_RUN_TAG = "SHELL_RUN"

const shell_run_skill = """
If you asked to run an sh block. Never do it! You MUSTN'T run any sh block, it will be run by the SYSTEM later! 
You propose the sh script that should be run in a most concise short way and wait for feedback!

Assume all standard tools are available - do not attempt installations.

Format:
Each shell commands which you propose will be found in the corresponing next user message with the format like: 
<$SHELL_RUN_TAG command $ONELINER_SS>

Feedback will be provided in the next message as:
- Shell script: between ```sh and ``` tags
- Results: between ```sh_run_result and ``` tags
"""

const shell_skill = Skill(
    name=SHELL_RUN_TAG,
    skill_description=shell_run_skill,
    stop_sequence=ONELINER_SS
)

@kwdef struct ShellCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "sh"
    content::String
    kwargs::Dict{String,String} = Dict{String,String}()
end

function ShellCommand(cmd::Command)
    language, content = parse_code_block(cmd.content)
    ShellCommand(language=language, content=content, kwargs=cmd.kwargs)
end

function execute(cmd::ShellCommand; no_confirm=false)
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
    return format_cmd_output(output, error, "", process)
end