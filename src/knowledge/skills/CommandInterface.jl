# Command interfaces.

abstract type AbstractTag end
abstract type AbstractCommand end


preprocess(cmd::AbstractCommand) = cmd
execute(cmd::AbstractCommand) = @warn "Unimplemented \"execute\" for $(typeof(cmd))"

"""
usually stop_sequence and commandname are static for type
"""
commandname(cmd::Type{<:AbstractCommand})::String = (@warn "Unimplemented \"name\" for $(typeof(cmd))"; return "")
commandname(cmd::AbstractCommand)::String 				= commandname(typeof(cmd))
stop_sequence(cmd::Type{<:AbstractCommand})::String = (@warn "Unimplemented \"stop_sequence\" for $(typeof(cmd))"; return "")
stop_sequence(cmd::AbstractCommand)::String 				= stop_sequence(typeof(cmd))
has_stop_sequence(cmd::Type{<:AbstractCommand})::Bool = (@warn "Unimplemented \"has_stop_sequence\" for $(typeof(cmd))"; return false)
has_stop_sequence(cmd::AbstractCommand)::Bool         = has_stop_sequence(typeof(cmd))
get_description(cmd::Type{<:AbstractCommand})::String = (@warn "Unimplemented \"get_description\" for $(typeof(cmd))"; return "unknown skill! $(typeof(cmd))")
get_description(cmd::AbstractCommand)::String         = get_description(typeof(cmd))
