
const ChangeTracker = Dict{String, Symbol}

function (tracker::ChangeTracker)(src_content::Context)
	existing_keys = keys(src_content)
	filter!(pair -> pair.first in existing_keys, tracker)

	for (source, content) in src_content
		!haskey(tracker, source) && ((tracker[source] = :NEW); continue)
		new_content = get_updated_content(source)
		tracker[source] = content == get_chunk_standard_format(source, new_content) ? :UNCHANGED : :UPDATED
	end
	return tracker, src_content
end

function parse_source(source::String)
	parts = split(source, ':')
	length(parts) == 1 && return parts[1], nothing
	start_line, end_line = parse.(Int, split(parts[2], '-'))
	return parts[1], (start_line, end_line)
end

function get_updated_content(source::String)
	file_path, line_range = parse_source(source)
	!isfile(file_path) && (@warn "File not found: $file_path"; return nothing)
	lines = readlines(file_path)
	return isnothing(line_range) ? join(lines, "\n") : join(lines[line_range[1]:min(line_range[2], length(lines))], "\n")
end


to_string(tag::String, element::String, cb_ext::CodeBlockExtractor) = to_string(tag::String, element::String, cb_ext.shell_results)
to_string(tag::String, element::String, shell_results::AbstractDict{String, CodeBlock}) = begin
	return """
	<$tag>
	$(join(["""<$element shortened>
    $(get_shortened_code(codestr(codeblock)))
    </$element>
    <$(SHELL_RUN_RESULT)>
    $(codeblock.results[end])
    </$(SHELL_RUN_RESULT)>
    """ for (code, codeblock) in shell_results], "\n"))
	</$tag>
	"""
end

to_string(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = format_tag(tag, element, scr_state, src_cont)
format_tag(tag::String, element::String, scr_state::ChangeTracker, src_cont::Context) = begin
	output = ""
	new_files = format_element(element, scr_state, src_cont, :NEW)
	if !is_really_empty(new_files)
		output *= """
		<$tag NEW>
		$new_files
		</$tag>
		"""
	end
	updated_files = format_element(element, scr_state, src_cont, :UPDATED)
	if !is_really_empty(updated_files)
		output *= """
		<$tag UPDATED>
		$updated_files
		</$tag>
		"""
	end
	output
end
format_element(element::String, scr_state::ChangeTracker, src_cont::Context, state::Symbol) = begin
	join(["""
<$element>
$content
</$element>
""" for (src,content) in src_cont if scr_state[src] == state], '\n')
end