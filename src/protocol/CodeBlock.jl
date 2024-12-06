@kwdef mutable struct CodeBlock <: BLOCK
    type::Symbol = :NOTHING
    language::String
    file_path::String
    root_path::String
    content::String
    postcontent::String = ""
    run_results::Vector{String} = []
end

# Constructor to set the id based on content hash

to_dict(cb::CodeBlock)= Dict(
	"type"        => cb.type,
	"language"    => cb.language,
	"file_path"   => cb.file_path,
	"root_path"   => cb.root_path,
	"content"     => cb.content,
	"postcontent" => cb.postcontent,
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

codestr(cb::CodeBlock) = cb.type == :MODIFY  ? process_modify_command(parse_source(cb.file_path)[1], cb.postcontent, cb.root_path) :
                         cb.type == :CREATE  ? process_create_command(cb.file_path, cb.content) :
                         cb.type == :DEFAULT ? cb.content :
                         error("not known type for cb")

get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"




# function format_shell_results_to_context(shell_commands::AbstractDict{String, CodeBlock})
# 	inner = join(["""<sh_script shortened>
#     $(get_shortened_code(codestr(codeblock)))
#     </sh_script>
#     <sh_output>
#     $(codeblock.results[end])
#     </sh_output>
#     """ for (code, codeblock) in shell_commands], "\n")
# 	content = """
# 	<ShellRunResults>
# 	$inner
# 	</ShellRunResults>
# 	"""
# 	return content
# end

@kwdef mutable struct WebCodeBlock <: BLOCK
	id::String  # We'll set this in the constructor
	type::Symbol = :NOTHING
	language::String
	file_path::String
	content::String
	postcontent::String = ""
	run_results::Vector{String} = []
end

function WebCodeBlock(type::Symbol, language::String, file_path::String, content::String, postcontent::String = "", run_results::Vector{String} = [])
    id = bytes2hex(sha256(content))
    WebCodeBlock(id, type, language, file_path, content, postcontent, run_results)
end

to_dict(cb::WebCodeBlock)= Dict(
	"id"          => cb.id,
	"type"        => cb.type,
	"language"    => cb.language,
	"file_path"   => cb.file_path,
	"content"     => cb.content,
	"postcontent"     => cb.postcontent,
	"run_results" => cb.run_results)
