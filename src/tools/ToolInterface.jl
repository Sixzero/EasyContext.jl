# Tool interfaces.

# Tool description format - CallFormat only (function-call style)
# Format: "tool_name(param: value)" style
const TOOL_DESCRIPTION_FORMAT = :call

"""
Tool execution flow and safety checks:

┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐
  ToolTag                 Parsed from LLM output by Agent
└─ ─ ─ ─┬─ ─ ─ ─ ─ ─ ─ ─┘
        │
--------▼----------- Tool Interface Implementation
┌───────────────┐
│ Tool(tag)     │ Construct Tool instance from ToolTag
└───────┬───────┘
        │
        ▼
┌─ ─ ─ ─┴─ ─ ─ ─┐
  LLM_safetorun   Optional AI safety check before auto-execution
└─ ─ ─ ─┬─ ─ ─ ─┘   (e.g. verify shell commands without user prompt)
        │
        ▼
┌─ ─ ─ ─┴─ ─ ─ ─┐
  preprocess()    Optional content preparation
└─ ─ ─ ─┬─ ─ ─ ─┘   (e.g. LLM modifications, cursor-like instant apply)
        │
        ▼
┌───────────────┐
│ execute()     │ Performs the actual operation
└───────┬───────┘
--------│----------- End of Interface
        ▼
┌─ ─ ─ ─┴─ ─ ─ ─┐
  Results         Collected for LLM context
└─ ─ ─ ─ ─ ─ ─ ─┘

Interface methods:
- Constructor `Tool(tag::ToolTag)` - Creates Tool instance from parsed tag
- `create_tool(::Type{T}, tag::ToolTag)` - Creates Tool instance from parsed tag
- `preprocess(cmd::AbstractTool)` - Optional data preparation (e.g. LLM modifications)
- `execute(cmd::AbstractTool)` - Main operation implementation
- `LLM_safetorun(cmd::AbstractTool)` - Optional AI safety verification
- `toolname(::Type{<:AbstractTool})` - Tool's unique identifier
- `get_description(::Type{<:AbstractTool})` - Tool's usage documentation
- `get_cost(cmd::AbstractTool)` - Get the cost of tool execution (if applicable)

Note: The LLM output generation and ToolTag parsing are handled by the Agent.
Each Tool implementation must provide a constructor that takes a ToolTag.
"""
abstract type AbstractTool end

create_tool(::Type{T}, tag::ToolTag) where T <: AbstractTool = @warn "Unimplemented \"create_tool\" for $(T) $(join(stacktrace(), "\n"))"; return nothing
create_tool(tool::AbstractTool, tag::ToolTag) = @warn "Unimplemented \"create_tool\" for $(tool) $(join(stacktrace(), "\n"))"; return nothing
preprocess(tool::AbstractTool) = tool
get_id(tool::AbstractTool) = tool.id
execute(tool::AbstractTool) = @warn "Unimplemented \"execute\" for $(typeof(tool))"
get_cost(tool::AbstractTool) = nothing  # Default implementation returns nothing

"""
Check if tool execution was cancelled by user
"""
is_cancelled(tool::AbstractTool) = false

"""
Usually toolname is static for type
"""
toolname(tool::Type{<:AbstractTool})::String = (@warn "Unimplemented \"toolname\" for $(tool) $(join(stacktrace(), "\n"))"; return "")
toolname(tool::AbstractTool)::String = toolname(typeof(tool))
toolname(tool::Pair{String, T}) where T = first(tool)

get_description(tool::Type{<:AbstractTool})::String = (@warn "Unimplemented \"get_description\" for $(tool) $(join(stacktrace(), "\n"))"; return "unknown tool! $(tool)")
get_description(tool::AbstractTool)::String = get_description(typeof(tool))

get_extra_description(tool::Type{<:AbstractTool}) = nothing
get_extra_description(tool::AbstractTool) = nothing

"""
Specifies if tool uses single-line or multi-line format
Returns: :single_line or :multi_line
"""
tool_format(::Type{<:AbstractTool})::Symbol = :multi_line # Default to single line
tool_format(tool::AbstractTool)::Symbol = tool_format(typeof(tool))


result2string(tool::AbstractTool)::String = ""
resultimg2base64(tool::AbstractTool)::String = ""
resultaudio2base64(tool::AbstractTool)::String = ""

"""
Get tool schema for dynamic description generation.
Returns nothing by default (use legacy get_description).
Tools can override this to enable format-aware descriptions.

Returns: NamedTuple with (name, description, params) or nothing
  - params is a Vector of NamedTuple (name, type, description, required)
"""
get_tool_schema(::Type{<:AbstractTool}) = nothing
get_tool_schema(tool::AbstractTool) = get_tool_schema(typeof(tool))

"""
Generate a tool description from a schema.
Uses CallFormat's generate_tool_definition with the current default style.

Tools with schemas can use this in their get_description():

    get_description(::Type{MyTool}) = description_from_schema(get_tool_schema(MyTool))
"""
function description_from_schema(schema::NamedTuple)
    tool_schema = namedtuple_to_tool_schema(schema)
    generate_tool_definition(tool_schema)
end

description_from_schema(::Nothing) = "Unknown tool"

# This is a fallback, in case a model would forget tool calling request after the end of conversation, we automatically execute tools that REQUIRE execution, like CATFILE and WEBSEARCH and WORKSPACE_SEARCH
execute_required_tools(::Type{<:AbstractTool}) = false
execute_required_tools(tool::AbstractTool) = execute_required_tools(typeof(tool))

"""
    get_tool_map(tools) -> Dict{String, Any}

Create a mapping from tool names to tool types/instances for fast lookup.

Takes a vector of tool types or tool generator instances and returns
a Dict mapping tool names to the corresponding type/instance.

Example:
    tools = [ShellBlockTool, CatFileTool, edge_tool_instance]
    tool_map = get_tool_map(tools)
    # tool_map["bash"] => ShellBlockTool
    # tool_map["cat_file"] => CatFileTool
"""
function get_tool_map(tools::Vector)
    tool_map = Dict{String, Any}()
    for tool in tools
        name = toolname(tool)
        !isempty(name) && (tool_map[name] = tool)
    end
    tool_map
end
