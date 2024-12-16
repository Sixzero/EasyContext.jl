# Command interfaces.

abstract type AbstractCommand end
abstract type AbstractTag end


preprocess(cmd::AbstractCommand) = cmd
execute(cmd::AbstractCommand) = @warn "Unimplemented \"execute\" for $(typeof(cmd))"
has_stop_sequence(cmd::AbstractCommand) = @warn "Unimplemented \"has_stop_sequence\" for $(typeof(cmd))"
get_description(cmd::AbstractCommand) = @warn "Unimplemented \"get_description\" for $(typeof(cmd))"

"""
usually stop_sequence and commandname are static for type
"""
stop_sequence(cmd::Type{<:AbstractCommand}) = @warn "Unimplemented \"stop_sequence\" for $(typeof(cmd))"
stop_sequence(cmd::AbstractCommand) = stop_sequence(typeof(cmd))
commandname(cmd::Type{<:AbstractCommand}) = @warn "Unimplemented \"name\" for $(typeof(cmd))"
commandname(cmd::AbstractCommand) = commandname(typeof(cmd))
