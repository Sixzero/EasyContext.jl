# ToolInterface.jl - Re-exports from ToolCallFormat
#
# All tool interface types and functions are now in ToolCallFormat.jl
# This file re-exports them for backward compatibility.

using ToolCallFormat: AbstractTool, CodeBlock
using ToolCallFormat: create_tool, preprocess, execute, get_id, is_cancelled
using ToolCallFormat: toolname, get_description, get_tool_schema, get_extra_description
using ToolCallFormat: result2string, resultimg2base64, resultaudio2base64
using ToolCallFormat: execute_required_tools, get_cost, tool_format
using ToolCallFormat: description_from_schema
using ToolCallFormat: ParsedCall, ToolSchema, ParamSchema
using ToolCallFormat: CallStyle, CONCISE, PYTHON, MINIMAL, TYPESCRIPT
using ToolCallFormat: get_default_call_style, generate_tool_definition
using ToolCallFormat: @tool, @deftool
