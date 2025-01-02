# Command interfaces.

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

