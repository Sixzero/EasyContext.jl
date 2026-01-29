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
DEPRECATED: Convert ParsedCall to ToolTag for compatibility.
Use ParsedCall directly with create_tool(::Type{T}, call::ParsedCall) instead.
This function is kept for backward compatibility with tests and legacy code.
"""
function to_tool_tag(call::ParsedCall; kwargs::AbstractDict=Dict())::ToolTag
    # Convert ParsedValue dict to String dict (taking value field)
    converted_kwargs = Dict{String, Any}()
    for (k, v) in call.kwargs
        converted_kwargs[k] = v.value
    end

    # Merge with additional kwargs
    merged_kwargs = merge(converted_kwargs, Dict(kwargs))

    ToolTag(
        name=call.name,
        args="",  # Not used in new format
        content=call.content,
        kwargs=merged_kwargs
    )
end

"""
Serialize a ToolTag to function-call format.
"""
function serialize_tool_tag(tag::ToolTag; style::CallStyle=CONCISE)::String
    if !isempty(tag.kwargs)
        if isempty(tag.content)
            return serialize_tool_call(tag.name, tag.kwargs; style)
        else
            return serialize_tool_call_with_content(tag.name, tag.kwargs, tag.content; style)
        end
    end

    if !isempty(tag.args)
        kwargs = Dict{String, Any}("args" => tag.args)
        if isempty(tag.content)
            return serialize_tool_call(tag.name, kwargs; style)
        else
            return serialize_tool_call_with_content(tag.name, kwargs, tag.content; style)
        end
    end

    if isempty(tag.content)
        return "$(tag.name)()"
    else
        return serialize_tool_call_with_content(tag.name, Dict{String, Any}(), tag.content; style)
    end
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

export namedtuple_to_tool_schema, to_tool_tag, serialize_tool_tag, input_schema_to_tool_schema
