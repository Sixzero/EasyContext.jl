# Bridges between native API tool calls and ToolCallFormat types
using OpenRouter: Tool, get_arguments
using ToolCallFormat: ParsedCall, ParsedValue, ToolSchema, ParamSchema

export to_openrouter_tool, to_parsed_call, try_to_parsed_call

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
    "object[]" => "array",
    "array"    => "array",
    "object"   => "object",
    "codeblock"=> "string",
)

# CLIProxyAPI cloaks Claude OAuth requests as Claude Code, which never declares custom tool
# names — so it rewrites every one of ours into an opaque `mcp__<hmac>__<hmac>_<name>` alias and
# maps it back on the response. Weaker models (haiku, used by the subagents) don't reproduce the
# opaque digests verbatim, the reverse lookup fails and the whole stream dies with
# "cannot restore Claude OAuth MCP tool alias ...: no unique request-local match".
# A name that ALREADY looks like an MCP tool is passed through untouched (its
# `IsClaudeMCPToolName` check short-circuits the aliasing), so we do the renaming ourselves with
# a fixed, reversible prefix: no per-request symbol table, nothing to fail to restore.
# Reversed in `to_parsed_call` below. Harmless for every other provider (plain [A-Za-z0-9_] name).
# The skip only holds within Anthropic's 64-char tool-name limit — a longer name fails
# `IsClaudeMCPToolName` and would be aliased anyway. Machine aliases embed user-controlled
# device names, so a name that doesn't fit is left bare (old behaviour) rather than
# truncated: truncating would make the reverse lookup resolve to a nonexistent tool.
const NATIVE_TOOL_PREFIX = "mcp__tfa__"
const MAX_NATIVE_TOOL_NAME = 64

_prefix_tool_name(name::AbstractString) =
    (startswith(name, NATIVE_TOOL_PREFIX) ||
     length(name) + length(NATIVE_TOOL_PREFIX) > MAX_NATIVE_TOOL_NAME) ? String(name) :
    NATIVE_TOOL_PREFIX * name
_unprefix_tool_name(name::AbstractString) = String(chopprefix(name, NATIVE_TOOL_PREFIX))

"""Convert a ToolSchema or NamedTuple schema to an OpenRouter.Tool (JSON Schema params)."""
to_openrouter_tool(schema::ToolSchema) = _schema_to_tool(schema.name, schema.description, schema.params)
to_openrouter_tool(schema::NamedTuple) = _schema_to_tool(schema.name, schema.description, schema.params)

function _schema_to_tool(name::String, description::String, params)::Tool
    properties = Dict{String,Any}()
    required = String[]
    for p in params
        prop = Dict{String,Any}("type" => get(PARAM_TYPE_TO_JSON, p.type, "string"))
        desc_parts = String[]
        !isempty(p.description) && push!(desc_parts, p.description)
        default_val = hasproperty(p, :default) ? p.default : nothing
        default_val !== nothing && push!(desc_parts, "(default: $(default_val))")
        !isempty(desc_parts) && (prop["description"] = join(desc_parts, " "))
        p.type == "string[]" && (prop["items"] = Dict("type" => "string"))
        p.type == "object[]" && (prop["items"] = Dict("type" => "object"))
        p.type == "array" && !haskey(prop, "items") && (prop["items"] = Dict("type" => "string"))
        properties[p.name] = prop
        p.required && push!(required, p.name)
    end
    Tool(; name=_prefix_tool_name(name), description, parameters=Dict{String,Any}(
        "type" => "object", "properties" => properties, "required" => required))
end

"""Convert an API tool_call dict to a ParsedCall, using OpenRouter.get_arguments for JSON parsing."""
function to_parsed_call(tc::Dict)::ParsedCall
    fn = tc["function"]
    args = get_arguments(tc)
    kwargs = Dict{String,ParsedValue}(
        k => ParsedValue(value=v, raw=string(v)) for (k, v) in args
    )
    ParsedCall(name=_unprefix_tool_name(fn["name"]), kwargs=kwargs)
end

"""
Like `to_parsed_call`, but returns `nothing` when the tool-call `arguments` JSON cannot be
parsed. Tool-call arguments stream as a JSON string; a dropped delta or an early stream close
yields truncated JSON, so `JSON3.read` throws `ArgumentError`. Returning `nothing` lets callers
keep the native round-trip valid (emit an error result for this call) instead of aborting the
whole batch. Any other error is a real bug and is rethrown.
"""
function try_to_parsed_call(tc::Dict)::Union{ParsedCall, Nothing}
    try
        to_parsed_call(tc)
    catch e
        e isa ArgumentError || rethrow()
        @warn "Failed to parse native tool_call arguments (truncated stream?)" tool_name=get(get(tc, "function", Dict()), "name", "?") exception=e
        nothing
    end
end
