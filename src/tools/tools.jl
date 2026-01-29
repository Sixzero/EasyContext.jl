
# STOP_SEQUENCE is deprecated - CallFormat doesn't use stop sequences
# Kept as "#RUN" to detect if it's accidentally used somewhere
const STOP_SEQUENCE = "#RUN"

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

include("AbstractExtractor.jl")
include("ToolTagExtractor.jl")

export ShellBlockTool, SendKeyTool, CatFileTool, ClickTool, CreateFileTool, ModifyFileTool, WebSearchTool, WorkspaceSearchTool, JuliaSearchTool
export toolname, get_description, get_tool_schema, description_from_schema, stop_sequence, has_stop_sequence

# CallFormat exports (now from ToolCallFormat.jl)
export CallStyle, CONCISE, PYTHON, MINIMAL, TYPESCRIPT
export ToolSchema, ParamSchema, ToolFormatConfig, CallFormatConfig
export ParsedValue, ParsedCall
export generate_tool_definition, generate_tool_definitions, generate_format_documentation, generate_system_prompt
export get_default_call_style, set_default_call_style!
export simple_tool_schema, code_tool_schema
export short_type, python_type
export namedtuple_to_tool_schema
# Streaming/parsing
export StreamProcessor, StreamState, process_chunk!, finalize!, reset!, parse_tool_call
# Serialization
export serialize_value, serialize_tool_call, serialize_parsed_call

export STOP_SEQUENCE