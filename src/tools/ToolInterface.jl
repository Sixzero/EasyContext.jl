# Tool interfaces.

"""
Tool execution flow and safety checks:

┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐
  LLM Output
  then     
  Parse ToolTag structs     
└─ ─ ─ ─┬─ ─ ─ ─ ─ ─ ─ ─┘
        │
--------▼----------- Tool Interface Implementation 
┌───────────────┐
│ instantiate() │ Creates Tool instance from ToolTag
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
- `instantiate(::Val{T}, cmd::ToolTag)` - Factory method for tool creation from parsed tag
- `preprocess(cmd::AbstractTool)` - Optional data preparation (e.g. cursor-like instant apply)
- `execute(cmd::AbstractTool)` - Main operation implementation
- `LLM_safetorun(cmd::AbstractTool)` - Optional AI safety verification, to skip user confirmation before execute
- `toolname(cmd)` - Tool's unique identifier 
- `stop_sequence(cmd)` - Tool termination marker (if needed)
- `get_description(cmd)` - Tool's usage documentation

Note: The LLM output generation and ToolTag parsing are handled externally by the LLM_solve.jl 
and parser.jl modules. This interface focuses on the tool implementation after a ToolTag is received.
"""
abstract type AbstractTag end
abstract type AbstractTool end

instantiate(::Val{T}, tag::AbstractTag) where T = @error "Unimplemented \"instantiate\" for symbol: $T\n its should be possible to create from tag:\n$tag"
preprocess(tool::AbstractTool) = tool
execute(tool::AbstractTool) = @warn "Unimplemented \"execute\" for $(typeof(tool))"

"""
usually stop_sequence and toolname are static for type
"""
toolname(::Type{<:AbstractTool})::String = (@warn "Unimplemented \"toolname\" for $(typeof(tool))"; return "")
toolname(tool::AbstractTool)::String = toolname(typeof(tool))
stop_sequence(::Type{<:AbstractTool})::String = (@warn "Unimplemented \"stop_sequence\" for $(typeof(tool))"; return "")
stop_sequence(tool::AbstractTool)::String = stop_sequence(typeof(tool))
get_description(::Type{<:AbstractTool})::String = (@warn "Unimplemented \"get_description\" for $(typeof(tool))"; return "unknown skill! $(typeof(tool))")
get_description(tool::AbstractTool)::String = get_description(typeof(tool))

has_stop_sequence(::Type{<:AbstractTool})::Bool = stop_sequence(tool_type) != "" #This line was causing an error, assuming tool_type should be replaced with the type itself.
has_stop_sequence(tool::AbstractTool)::Bool = has_stop_sequence(typeof(tool))

