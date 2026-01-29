# Tool names for CallFormat (lowercase function-call style)
const CATFILE_TAG 	    = "cat_file"
const SENDKEY_TAG 	    = "send_key"
const CLICK_TAG  		    = "click"
const SHELL_BLOCK_TAG   = "bash"
const CREATE_FILE_TAG   = "create_file"
const MODIFY_FILE_TAG   = "modify_file"
const EMAIL_TAG         = "email"
const WEB_SEARCH_TAG    = "web_search"
const END_OF_BLOCK_TAG  = "END_OF_BLOCK"  # Internal marker, not a tool name
const END_OF_CODE_BLOCK = "endblock"      # Internal marker, not a tool name

include("../contexts/CTX_julia.jl")
include("../contexts/CTX_workspace.jl")

include("utils.jl")
include("ToolTag.jl")
include("CallFormat.jl")  # Must come before ToolInterface
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

include("ToolMacros.jl")

include("AbstractExtractor.jl")
# ToolTagExtractor removed - use CallExtractor from agent or provide your own AbstractExtractor

export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool, WebSearchTool, WorkspaceSearchTool, JuliaSearchTool
export toolname, get_description, get_tool_schema, description_from_schema

# CallFormat utilities (uses ToolCallFormat internally)
export namedtuple_to_tool_schema, to_tool_tag, serialize_tool_tag, input_schema_to_tool_schema

# Tool definition macro
export @tool