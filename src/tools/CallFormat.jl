# CallFormat - Tool description format system
# Re-exports from ToolCallFormat.jl for consistent tool description generation

# Import and re-export everything from ToolCallFormat
using ToolCallFormat

# Re-export types
export CallStyle, CONCISE, PYTHON, MINIMAL, TYPESCRIPT
export ToolFormatConfig, CallFormatConfig
export ParamSchema, ToolSchema
export ParsedValue, ParsedCall

# Re-export functions
export generate_tool_definition, generate_tool_definitions
export generate_format_documentation, generate_system_prompt
export get_default_call_style, set_default_call_style!
export simple_tool_schema, code_tool_schema
export short_type, python_type

# Re-export streaming/parsing
export StreamProcessor, StreamState
export STREAMING_TEXT, BUFFERING_IDENTIFIER, IN_TOOL_CALL, AFTER_PAREN, IN_CONTENT_BLOCK
export process_chunk!, finalize!, reset!
export parse_tool_call

# Re-export serialization
export serialize_value, serialize_tool_call, serialize_parsed_call
export serialize_tool_call_multiline, serialize_tool_call_with_content
export serialize_tool_schema, get_kv_separator

# ============================================================================
# EasyContext-specific additions
# ============================================================================

"""
Convert a NamedTuple schema to ToolSchema.
This allows tools using the old NamedTuple format to work with CallFormat.
"""
function namedtuple_to_tool_schema(schema::NamedTuple)::ToolSchema
    params = ParamSchema[]
    for p in get(schema, :params, [])
        push!(params, ParamSchema(
            name=string(p.name),
            type=string(get(p, :type, "string")),
            description=string(get(p, :description, "")),
            required=get(p, :required, true)
        ))
    end
    ToolSchema(
        name=string(schema.name),
        params=params,
        description=string(get(schema, :description, ""))
    )
end

export namedtuple_to_tool_schema
