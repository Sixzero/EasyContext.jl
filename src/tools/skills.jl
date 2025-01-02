
const STOP_SEQUENCE = "#RUN"


const CATFILE_TAG 	    = "CATFILE"
const SENDKEY_TAG 	    = "SENDKEY"
const CLICK_TAG  		    = "CLICK"
const SHELL_BLOCK_TAG   = "SHELL_BLOCK"
const CREATE_FILE_TAG   = "CREATE"
const MODIFY_FILE_TAG   = "MODIFY"
const EMAIL_TAG         = "EMAIL"
const WEB_SEARCH_TAG    = "WEB_SEARCH"
const END_OF_BLOCK_TAG  = "END_OF_BLOCK"
const END_OF_CODE_BLOCK = "endblock"
const allowed_commands::Set{String} = Set([MODIFY_FILE_TAG, CREATE_FILE_TAG, EMAIL_TAG, CLICK_TAG, SHELL_BLOCK_TAG, SENDKEY_TAG, CATFILE_TAG])

include("utils.jl")
include("ToolTag.jl")
include("ClickTool.jl")
include("SendKeyTool.jl")
include("ShellBlockTool.jl")
include("CatFileTool.jl")
include("ModifyFileTool.jl")
include("CreateFileTool.jl")
include("WebSearchTool.jl")
include("EmailTool.jl")

include("parser.jl")

export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool, EmailTool, WebSearchTool
export commandname, get_description, stop_sequence, has_stop_sequence
