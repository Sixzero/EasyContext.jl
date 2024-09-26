
const ChangeTracker = Dict{String, Tuple{Symbol, String}}

function (tracker::ChangeTracker)(src_content::Context)
	# Check for new and updated sources
	for (source, content) in src_content
		!haskey(tracker, source) && ((tracker[source] = (:NEW, content)); continue)

		new_content = get_updated_content(source)
		if content == new_content
			tracker[source] = (:UNCHANGED, content)
		else
			tracker[source] = (:UPDATED, new_content)
		end
	end
	
	existing_keys = keys(src_content)
	filter!(pair -> pair.first in existing_keys, tracker)
	return tracker
end

function get_updated_content(source::String)
	file_path, line_range = parse_source(source)
	!isfile(file_path) && (@warn "File not found: $file_path"; return nothing)
	return isnothing(line_range) ? read(file_path, String) : join(lines[start_line:min(end_line, length(lines))], "\n")
end