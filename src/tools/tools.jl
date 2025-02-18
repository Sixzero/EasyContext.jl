
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

include("utils.jl")
include("ToolTag.jl")
include("ClickTool.jl")
include("SendKeyTool.jl")
include("ShellBlockTool.jl")
include("CatFileTool.jl")
include("ModifyFileTool.jl")
include("CreateFileTool.jl")
include("WebSearchTool.jl")

include("AbstractExtractor.jl")
include("ToolTagExtractor.jl")

export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool, WebSearchTool
export toolname, get_description, stop_sequence, has_stop_sequence

export STOP_SEQUENCE