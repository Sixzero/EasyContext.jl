# CallFormat - Tool call format utilities
# Uses ToolCallFormat.jl internally for parsing/serialization types.

using ToolCallFormat: ToolSchema, ParamSchema, ParsedCall, ParsedValue
using ToolCallFormat: CallStyle, CONCISE
using ToolCallFormat: generate_tool_definition
using ToolCallFormat: serialize_tool_call, serialize_tool_call_with_content

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

"""
Convert an MCP InputSchema to a ToolSchema for CallFormat generation.
"""
function input_schema_to_tool_schema(name::String, description::String, input_schema)::ToolSchema
    properties = something(input_schema.properties, Dict())
    required_set = Set(something(input_schema.required, String[]))

    params = ParamSchema[]
    for (param_name, details) in properties
        param_type = get(details, "type", "string")
        param_desc = get(details, "description", "")
        is_required = string(param_name) in required_set
        push!(params, ParamSchema(
            name=string(param_name),
            type=param_type,
            description=param_desc,
            required=is_required
        ))
    end

    ToolSchema(name=name, params=params, description=description)
end

export namedtuple_to_tool_schema, input_schema_to_tool_schema
