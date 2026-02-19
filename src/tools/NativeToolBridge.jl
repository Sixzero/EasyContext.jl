# Bridges between native API tool calls and ToolCallFormat types
using OpenRouter: Tool, get_arguments
using ToolCallFormat: ParsedCall, ParsedValue, ToolSchema, ParamSchema

export to_openrouter_tool, to_parsed_call

const PARAM_TYPE_TO_JSON = Dict(
    "string"   => "string",
    "str"      => "string",
    "number"   => "number",
    "num"      => "number",
    "integer"  => "integer",
    "int"      => "integer",
    "boolean"  => "boolean",
    "bool"     => "boolean",
    "null"     => "null",
    "string[]" => "array",
    "array"    => "array",
    "object"   => "object",
    "codeblock"=> "string",
)

"""Convert a ToolSchema or NamedTuple schema to an OpenRouter.Tool (JSON Schema params)."""
to_openrouter_tool(schema::ToolSchema) = _schema_to_tool(schema.name, schema.description, schema.params)
to_openrouter_tool(schema::NamedTuple) = _schema_to_tool(schema.name, schema.description, schema.params)

function _schema_to_tool(name::String, description::String, params)::Tool
    properties = Dict{String,Any}()
    required = String[]
    for p in params
        prop = Dict{String,Any}("type" => get(PARAM_TYPE_TO_JSON, p.type, "string"))
        !isempty(p.description) && (prop["description"] = p.description)
        p.type == "string[]" && (prop["items"] = Dict("type" => "string"))
        properties[p.name] = prop
        p.required && push!(required, p.name)
    end
    Tool(; name, description, parameters=Dict{String,Any}(
        "type" => "object", "properties" => properties, "required" => required))
end

"""Convert an API tool_call dict to a ParsedCall, using OpenRouter.get_arguments for JSON parsing."""
function to_parsed_call(tc::Dict)::ParsedCall
    fn = tc["function"]
    args = get_arguments(tc)
    kwargs = Dict{String,ParsedValue}(
        k => ParsedValue(value=v, raw=string(v)) for (k, v) in args
    )
    ParsedCall(name=fn["name"], kwargs=kwargs)
end
