
@kwdef mutable struct Condition
	patterns::Dict{String, Symbol}
	response::Symbol=:UNKNOWN
end

parse(c::Condition, conv) = parse(c,conv.messages[end].content)
parse(c::Condition, response::String) = begin
	ke=collect(keys(c.patterns))
	best_match = findmax(pattern -> occursin(pattern, response) ? length(pattern) : -1, ke )
	@show best_match
	return best_match[1] > 0 ? c.patterns[ke[best_match[2]]] : :UNMATCHED
end