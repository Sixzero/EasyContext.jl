import Base
using PromptingTools: AbstractMessage

@kwdef mutable struct Condition{T}
	patterns::Dict{String, T}
end

(c::Condition{Q})(conv::T) where {T<:AbstractMessage, Q} = parse(c,String(conv.content))
(c::Condition{Q})(response::String) where {Q} = parse(c,response)
Base.parse(c::Condition{Q}, conv::T) where {T<:AbstractMessage, Q} = parse(c,String(conv.content))
Base.parse(c::Condition{Q}, response::String) where {Q} = begin
	ke=collect(keys(c.patterns))
	best_match = findmax(pattern -> occursin(pattern, response) ? length(pattern) : -1, ke )
	# @show best_match
	return best_match[1] > 0 ? c.patterns[ke[best_match[2]]] : nothing
end
