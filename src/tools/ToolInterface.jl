# ToolInterface.jl - Re-exports from ToolCallFormat
#
# All tool interface types and functions are now in ToolCallFormat.jl
# This file re-exports them for backward compatibility.
#
# Note: Use `import` not `using` for functions that tools need to extend.

import ToolCallFormat
import ToolCallFormat: create_tool, execute, get_id, is_cancelled
import ToolCallFormat: toolname, get_description, get_tool_schema, get_extra_description
import ToolCallFormat: result2string, resultimg2base64, resultaudio2base64
import ToolCallFormat: is_executable, get_cost

using ToolCallFormat: AbstractTool, TextBlock
using ToolCallFormat: description_from_schema, get_tool_type
using ToolCallFormat: ParsedCall, ToolSchema, ParamSchema
using ToolCallFormat: CallStyle, CONCISE, PYTHON, MINIMAL, TYPESCRIPT
using ToolCallFormat: get_default_call_style, generate_tool_definition
using ToolCallFormat: @deftool
