
const STOP_SEQUENCE = "#RUN"
const MULTILINER_SS = STOP_SEQUENCE*">"
const ONELINER_SS   = STOP_SEQUENCE*"/>"


const CATFILE_TAG 	   = "CATFILE"
const SENDKEY_TAG 	   = "SENDKEY"
const CLICK_TAG  		   = "CLICK"
const SHELL_BLOCK_TAG  = "SHELL_BLOCK"
const CREATE_FILE_TAG  = "CREATE"
const MODIFY_FILE_TAG  = "MODIFY"
const EMAIL_TAG        = "EMAIL"
const WEB_SEARCH_TAG   = "WEB_SEARCH"
const END_OF_BLOCK_TAG = "ENDOFBLOCK"
const allowed_commands::Set{String} = Set([MODIFY_FILE_TAG, CREATE_FILE_TAG, EMAIL_TAG, CLICK_TAG, SHELL_BLOCK_TAG, SENDKEY_TAG, CATFILE_TAG])

include("skill.jl")
include("utils.jl")
include("command.jl")
include("ClickCommand.jl")
include("SendKeyCommand.jl")
include("ShellBlockCommand.jl")
include("CatFileCommand.jl")
include("CreateFileCommand.jl")
include("ModifyFileCommand.jl")
include("WebSearchCommand.jl")
include("EmailCommand.jl")

include("parser.jl")

export ShellBlockCommand, SendKeyCommand, CatFileCommand, ClickCommand, CreateFileCommand, ModifyFileCommand, EmailCommand
export shell_block_skill, key_skill, catfile_skill, click_skill, create_file_skill, modify_file_skill, email_skill
