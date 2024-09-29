
abstract type BLOCK end

@kwdef mutable struct CodeBlock <: BLOCK
	type::Symbol = :NOTHING
	language::String
	file_path::String
	pre_content::String
	content::String = ""
	run_results::Vector{String} = []
end

# Constructor to set the id based on pre_content hash


to_dict(cb::CodeBlock)= Dict(
	"type"        => cb.type,
	"language"    => cb.language,
	"file_path"   => cb.file_path,
	"pre_content" => cb.pre_content,
	"content"     => cb.content,
	"run_results" => cb.run_results)


function get_shortened_code(code::String, head_lines::Int=4, tail_lines::Int=3)
	lines = split(code, '\n')
	total_lines = length(lines)
	
	if total_lines <= head_lines + tail_lines
			return code
	else
			head = join(lines[1:head_lines], '\n')
			tail = join(lines[end-tail_lines+1:end], '\n')
			return "$head\n...\n$tail"
	end
end


codestr(cb::CodeBlock) =  if     cb.type==:MODIFY  return process_modify_command(cb.file_path, cb.content)
													elseif cb.type==:CREATE  return process_create_command(cb.file_path, cb.content)
													elseif cb.type==:DEFAULT return cb.content
													else @assert false "not known type for $cb"
end
get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"
process_modify_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
	"meld $(file_path) <(cat <<'$delimiter'\n$(content)\n$delimiter\n)"
end
process_create_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
	"cat > $(file_path) <<'$delimiter'\n$(content)\n$delimiter"
end

function format_shell_results_to_context(shell_commands::AbstractDict{String, CodeBlock})
	inner = join(["""<sh_script shortened>
    $(get_shortened_code(codestr(codeblock)))
    </sh_script>
    <sh_output>
    $(codeblock.results[end])
    </sh_output>
    """ for (code, codeblock) in shell_commands], "\n")
	content = """
	<ShellRunResults>
	$inner
	</ShellRunResults>
	"""
	return content
end



@kwdef mutable struct WebCodeBlock <: BLOCK
	id::String  # We'll set this in the constructor
	type::Symbol = :NOTHING
	language::String
	file_path::String
	pre_content::String
	content::String = ""
	run_results::Vector{String} = []
end
function WebCodeBlock(type::Symbol, language::String, file_path::String, pre_content::String, content::String = "", run_results::Vector{String} = [])
	id = bytes2hex(sha256(pre_content))
	WebCodeBlock(id, type, language, file_path, pre_content, content, run_results)
end

to_dict(cb::WebCodeBlock)= Dict(
	"id"          => cb.id,
	"type"        => cb.type,
	"language"    => cb.language,
	"file_path"   => cb.file_path,
	"pre_content" => cb.pre_content,
	"content"     => cb.content,
	"run_results" => cb.run_results)