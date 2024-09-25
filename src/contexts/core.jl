abstract type AbstractContextCreator end


function get_cache_setting(::AbstractContextCreator, conv)
	printstyled("WARNING: get_cache_setting not implemented for this contexter type. Defaulting to no caching.\n", color=:red)
	return nothing
end








