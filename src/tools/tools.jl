
const STOP_SEQUENCE = "#RUN"


const CATFILE_TAG 	    = "READ"
const SENDKEY_TAG 	    = "SENDKEY"
const CLICK_TAG  		    = "CLICK"
const SHELL_BLOCK_TAG   = "BASH"
const CREATE_FILE_TAG   = "WRITE"
const MODIFY_FILE_TAG   = "UPDATE"
const EMAIL_TAG         = "EMAIL"
const WEB_SEARCH_TAG    = "WEB_SEARCH"
const END_OF_BLOCK_TAG  = "END_OF_BLOCK"
const END_OF_CODE_BLOCK = "endblock"

include("../contexts/CTX_julia.jl")
include("../contexts/CTX_workspace.jl")

include("utils.jl")
include("ToolTag.jl")
include("ToolInterface.jl")

include("ClickTool.jl")
include("SendKeyTool.jl")
include("ShellBlockTool.jl")
include("CatFileTool.jl")
include("ModifyFileTool.jl")
include("CreateFileTool.jl")
include("WebSearchTool.jl")
include("WorkspaceSearchTool.jl")
include("JuliaSearchTool.jl")

include("ToolGenerators.jl")

include("AbstractExtractor.jl")
include("ToolTagExtractor.jl")

export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool, WebSearchTool, WorkspaceSearchTool, JuliaSearchTool
export toolname, get_description, get_tool_schema, description_from_schema, stop_sequence, has_stop_sequence
export TOOL_DESCRIPTION_FORMAT

export STOP_SEQUENCE