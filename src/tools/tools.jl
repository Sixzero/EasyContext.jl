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
include("CallFormat.jl")  # Must come before ToolInterface
include("ToolInterface.jl")

# Tools using @deftool (simple)
include("ClickTool.jl")
include("SendKeyTool.jl")
include("NewTodoTool.jl")

# Tools with custom logic (manual)
include("ShellBlockTool.jl")
include("CatFileTool.jl")
include("ModifyFileTool.jl")
include("CreateFileTool.jl")
include("WebSearchTool.jl")
include("WorkspaceSearchTool.jl")
include("JuliaSearchTool.jl")

include("ToolGenerators.jl")

include("AbstractExtractor.jl")

# Export tool types
export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool
export WebSearchTool, WorkspaceSearchTool, JuliaSearchTool, NewTodoTool

# Note: Tool interface types and functions (AbstractTool, toolname, execute, etc.)
# should be imported directly from ToolCallFormat
