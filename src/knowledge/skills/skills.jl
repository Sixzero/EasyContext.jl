
const STOP_SEQUENCE = "#RUN"
const MULTILINER_SS = STOP_SEQUENCE*">"
const ONELINER_SS   = STOP_SEQUENCE*"/>"

include("skill.jl")
include("utils.jl")
include("command.jl")
include("command_click.jl")
include("command_sendkey.jl")
include("command_shell.jl")
include("command_cat_file.jl")
include("command_create_file.jl")
include("command_modify_file.jl")
include("command_email.jl")

include("parser.jl")

export ShellCommand, KeyCommand, CatFileCommand, ClickCommand, CreateFileCommand, ModifyFileCommand, EmailCommand
export shell_skill, key_skill, catfile_skill, click_skill, create_file_skill, modify_file_skill, email_skill

