
const STOP_SEQUENCE = "#RUN"


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

include("utils.jl")
include("CommandTag.jl")
include("ClickCommand.jl")
include("SendKeyCommand.jl")
include("ShellBlockCommand.jl")
include("CatFileCommand.jl")
include("ModifyFileCommand.jl")
include("CreateFileCommand.jl")
include("WebSearchCommand.jl")
include("EmailCommand.jl")

include("parser.jl")


export ShellBlockCommand, SendKeyCommand, CatFileCommand, ClickCommand, CreateFileCommand, ModifyFileCommand, EmailCommand, WebSearchCommand
export commandname, get_description, stop_sequence, has_stop_sequence
