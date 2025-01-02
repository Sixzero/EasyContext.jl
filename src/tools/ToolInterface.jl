# Command interfaces.

"""
Tool execution flow and safety checks:

┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐
  LLM Output
  then     
  Parse ToolTag structs     
└─ ─ ─ ┬ ─ ─ ─ ─ ─ ─ ─ ─┘
       │
-------▼------------ Tool Interface Implementation 
┌──────────────┐
│ instantiate()│ Creates concrete tool instance
└──────┬───────┘
       │
       ▼
┌─ ─ ─ ┴ ─ ─ ─┐
 LLM_safetorun  Optional AI safety verification
└─ ─ ─ ┬ ─ ─ ─┘
       │
       ▼
┌──────────────┐
│ preprocess() │ Data preparation, LLM processing
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  execute()   │ Performs the actual operation
└──────┬───────┘
-------│------------ End of Interface
       ▼
┌ ─ ─ ─┴─ ─ ─ ┐
  Results        Collected for LLM context
└ ─ ─ ─ ─ ─ ─ ┘

Interface methods:
- `instantiate(::Val{T}, cmd::ToolTag)` - Factory method for tool creation from parsed tag
- `preprocess(cmd::AbstractTool)` - Data preparation (e.g. LLM content modifications)
- `execute(cmd::AbstractTool)` - Main operation implementation
- `LLM_safetorun(cmd::AbstractTool)` - Optional AI safety verification
- `commandname(cmd)` - Tool's unique identifier
- `stop_sequence(cmd)` - Command termination marker (if needed)
- `get_description(cmd)` - Tool's usage documentation

Note: The LLM output generation and ToolTag parsing are handled externally by the LLM_solve.jl 
and parser.jl modules. This interface focuses on the tool implementation after a ToolTag is received.
"""
abstract type AbstractTag end
abstract type AbstractTool end

instantiate(::Val{T}, cmd::AbstractTag) where T = @error "Unimplemented \"instantiate\" for symbol: $T\n its should be possible to create from cmd:\n$cmd"
preprocess(cmd::AbstractTool) = cmd
execute(cmd::AbstractTool) = @warn "Unimplemented \"execute\" for $(typeof(cmd))"

"""
usually stop_sequence and commandname are static for type
"""
commandname(cmd::Type{<:AbstractTool})::String = (@warn "Unimplemented \"name\" for $(typeof(cmd))"; return "")
commandname(cmd::AbstractTool)::String 				= commandname(typeof(cmd))
stop_sequence(cmd::Type{<:AbstractTool})::String = (@warn "Unimplemented \"stop_sequence\" for $(typeof(cmd))"; return "")
stop_sequence(cmd::AbstractTool)::String 				= stop_sequence(typeof(cmd))
get_description(cmd::Type{<:AbstractTool})::String = (@warn "Unimplemented \"get_description\" for $(typeof(cmd))"; return "unknown skill! $(typeof(cmd))")
get_description(cmd::AbstractTool)::String         = get_description(typeof(cmd))

has_stop_sequence(cmd::Type{<:AbstractTool})::Bool = stop_sequence(cmd) != ""
has_stop_sequence(cmd::AbstractTool)::Bool        	= has_stop_sequence(typeof(cmd))

