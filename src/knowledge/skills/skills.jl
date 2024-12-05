
const STOP_SEQUENCE = "#RUN"
const MULTILINER_SS = STOP_SEQUENCE*">"
const ONELINER_SS   = STOP_SEQUENCE*"/>"


const CATFILE_TAG 	  = "CATFILE"
const SENDKEY_TAG 	  = "SENDKEY"
const CLICK_TAG  		  = "CLICK"
const SHELL_RUN_TAG   = "SHELL_RUN"
const CREATE_FILE_TAG = "CREATE"
const MODIFY_FILE_TAG = "MODIFY"
# const SHELL_BLOCK_TAG = "sh"
const EMAIL_TAG     	= "EMAIL"
const WEB_SEARCH_TAG  = "WEB_SEARCH"
const allowed_commands::Set{String} = Set([MODIFY_FILE_TAG, CREATE_FILE_TAG, EMAIL_TAG, CLICK_TAG, SHELL_RUN_TAG, SENDKEY_TAG, CATFILE_TAG])

include("skill.jl")
include("utils.jl")
include("command.jl")
include("command_click.jl")
include("command_sendkey.jl")
include("command_shell.jl")
include("command_cat_file.jl")
include("command_create_file.jl")
include("command_modify_file.jl")
include("command_websearch.jl")
include("command_email.jl")

include("parser.jl")

export ShellCommand, KeyCommand, CatFileCommand, ClickCommand, CreateFileCommand, ModifyFileCommand, EmailCommand
export shell_skill, key_skill, catfile_skill, click_skill, create_file_skill, modify_file_skill, email_skill
export shell_block_skill

