# CallFormat - Tool description format system
# Uses ToolCallFormat.jl internally, but does NOT re-export.
# Users who need ToolCallFormat should depend on it directly.

using ToolCallFormat: ToolSchema, ParamSchema, generate_tool_definition

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
