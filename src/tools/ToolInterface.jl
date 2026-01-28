# Tool interfaces.

# Tool description format: :block or :call
# :block = "TOOL_NAME args #RUN" style
# :call  = "tool_name(param: value)" style
# Change this and recompile to switch formats
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
- `stop_sequence(::Type{<:AbstractTool})` - Tool termination marker (if needed)
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
Usually stop_sequence and toolname are static for type
"""
toolname(tool::Type{<:AbstractTool})::String = (@warn "Unimplemented \"toolname\" for $(tool) $(join(stacktrace(), "\n"))"; return "")
toolname(tool::AbstractTool)::String = toolname(typeof(tool))
toolname(tool::Pair{String, T}) where T = first(tool)
stop_sequence(tool::Type{<:AbstractTool})::String = (@warn "Unimplemented \"stop_sequence\" for $(tool) $(join(stacktrace(), "\n"))"; return "")
stop_sequence(tool::AbstractTool)::String = stop_sequence(typeof(tool))
get_description(tool::Type{<:AbstractTool})::String = (@warn "Unimplemented \"get_description\" for $(tool) $(join(stacktrace(), "\n"))"; return "unknown tool! $(tool)")
get_description(tool::AbstractTool)::String = get_description(typeof(tool))

get_extra_description(tool::Type{<:AbstractTool}) = nothing
get_extra_description(tool::AbstractTool) = nothing

has_stop_sequence(tool::Type{<:AbstractTool})::Bool = stop_sequence(tool) != "" 
has_stop_sequence(tool::AbstractTool)::Bool = has_stop_sequence(typeof(tool))

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
Generate a tool description from a schema based on TOOL_DESCRIPTION_FORMAT.
Tools with schemas can use this in their get_description():

    get_description(::Type{MyTool}) = description_from_schema(get_tool_schema(MyTool))
"""
function description_from_schema(schema::NamedTuple)
    name = string(schema.name)
    desc = string(get(schema, :description, ""))
    params = get(schema, :params, [])

    if TOOL_DESCRIPTION_FORMAT == :call
        # Function call format: tool_name(param: type, ...)
        if isempty(params)
            param_str = ""
        else
            param_strs = String[]
            for p in params
                pname = string(p.name)
                ptype = string(get(p, :type, "string"))
                opt = get(p, :required, true) ? "" : "?"
                push!(param_strs, "$(pname)$(opt): $(ptype)")
            end
            param_str = join(param_strs, ", ")
        end
        return """$(desc)
$(name)($(param_str))"""
    else
        # Block format: TOOL_NAME <param> #RUN
        upper_name = uppercase(name)
        if isempty(params)
            param_str = ""
        else
            param_str = " " * join(["<$(p.name)>" for p in params], " ")
        end
        return """$(desc)
$(upper_name)$(param_str) #RUN"""
    end
end

description_from_schema(::Nothing) = "Unknown tool"

# This is a fallback, in case a model would forget tool calling request after the end of conversation, we automatically execute tools that REQUIRE execution, like CATFILE and WEBSEARCH and WORKSPACE_SEARCH
execute_required_tools(::Type{<:AbstractTool}) = false
execute_required_tools(tool::AbstractTool) = execute_required_tools(typeof(tool))

# const TOOL_REGISTRY = Dict{String, Type{<:AbstractTool}}()

# """
# Register a tool type with its name in the central registry.
# Usage: register_tool(MyTool) # automatically uses toolname(MyTool)
# Returns: true if registration was successful
# """
# function register_tool(::Type{T}) where T <: AbstractTool
#     name = toolname(T)
#     isempty(name) && error("Tool $(T) has no name defined")
    
#     haskey(TOOL_REGISTRY, name) && return false

#     # Validate required interface methods are implemented
#     for method in [:toolname, :get_description, :stop_sequence]
#         if !hasmethod(eval(method), (Type{T},))
#             error("Tool $(T) missing implementation for $(method)")
#         end
#     end

#     TOOL_REGISTRY[name] = T
#     return true
# end

# """
# Get list of registered tools with their descriptions
# """
# function list_tools()
#     sort!([
#         (name=name, type=T, desc=get_description(T))
#         for (name, T) in TOOL_REGISTRY
#     ])
# end

# # Tools can auto-register in their own modules:
# # __init__() = register_tool(MyTool)

