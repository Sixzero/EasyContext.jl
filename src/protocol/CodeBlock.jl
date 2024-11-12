

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

codestr(cb::CodeBlock) = cb.type == :MODIFY  ? process_modify_command(cb.file_path, cb.postcontent, cb.root_path) :
                         cb.type == :CREATE  ? process_create_command(cb.file_path, cb.content) :
                         cb.type == :DEFAULT ? cb.content :
                         error("not known type for cb")

get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"

function is_diff_service_available()
    try
        HTTP.get("http://localhost:3000/health", readtimeout=1)
        return true
    catch
        return false
    end
end

@enum Editor MELD VIMDIFF MELD_PRO
global CURRENT_EDITOR = MELD  # Default editor

function process_modify_command(file_path::String, content::String, root_path)
    delimiter = get_unique_eof(content)
    if CURRENT_EDITOR == VIMDIFF
        content_esced = replace(content, "'" => "\\'")
        "vimdiff $file_path <(echo -e '$content_esced')"
    elseif CURRENT_EDITOR == MELD_PRO
        if is_diff_service_available()
            # Use JSON3.write for proper JSON formatting and escaping
            payload = Dict(
                "leftPath" => file_path,
                "rightContent" => content,
                "pwd" => root_path
            )
            # Escape double quotes and wrap in single quotes for shell
            json_str = JSON3.write(payload)

            # Escape single quotes for shell
            json_str_for_shell = replace(json_str, "'" => "'\\''")
            """curl -X POST http://localhost:3000/diff -H "Content-Type: application/json" -d '$(json_str_for_shell)'"""
        else
            # fallback to meld
            "meld $file_path <(cat <<'$delimiter'\n$content\n$delimiter\n)"
        end
    else  # MELD
        "meld $file_path <(cat <<'$delimiter'\n$content\n$delimiter\n)"
    end
end

process_create_command(file_path::String, content::String) = begin
	delimiter = get_unique_eof(content)
	"cat > $(file_path) <<'$delimiter'\n$(content)\n$delimiter"
end

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
