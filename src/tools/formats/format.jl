function code_format(content::String, language::String="") 
	"""```$language
	$(strip(content))
	```$(END_OF_CODE_BLOCK)"""
end
function raw_format(content::String) 
	"""```
	$content
	```"""
end

function file_format(filepath::String, content::String, language::String="")
    return """
		# File: $filepath
    $(code_format(content, language))"""
end

function source_format(tag::String, filepath::String, content::String)
	"""$tag $filepath
	$(raw_format(content))"""
end

function email_format(to::String, subject::String, content::String)
	"""$(EMAIL_TAG) to=$to subject="$subject"
	$content
	$(END_OF_BLOCK_TAG)
	"""
end

function parse_code_block(content::String)
	lines = split(strip(content), '\n')
	first_line = first(lines)
	
	if startswith(first_line, "```")
			language = length(first_line) > 3 ? first_line[4:end] : "sh"
			content = join(lines[2:end-1], '\n')
			return language, content
	end
	
	return "sh", content
end

function parse_raw_block(content::String)
	content = strip(content)
	if startswith(content, "```")
		return join(split(content, '\n')[2:end-1], '\n')
	end
	return content
end


const SHELL_BLOCK_OPEN = "```sh"
const CODEBLOCK_CLOSE    = "```"
const SHELL_RUN_RESULT   = "```sh_run_result"
const WORKSPACE_TAG      = "Codebase"
const WORKSPACE_ELEMENT  = "File"
const JULIA_TAG          = "JuliaFunctions"
const JULIA_ELEMENT      = "Function"
const PYTHON_TAG         = "PythonPackages"
const PYTHON_ELEMENT     = "Package"

function workspace_ctx_2_string(new_chunks, updated_chunks)
	serialize(WORKSPACE_TAG, WORKSPACE_ELEMENT, new_chunks, updated_chunks)
end
julia_ctx_2_string(ctx_julia)               = julia_ctx_2_string(ctx_julia[1], ctx_julia[2])
julia_ctx_2_string(scr_state, src_cont)     = serialize(JULIA_TAG,     JULIA_ELEMENT, scr_state, src_cont)
python_ctx_2_string(ctx_python)             = python_ctx_2_string(ctx_python[1], ctx_python[2])
python_ctx_2_string(scr_state, src_cont)    = serialize(PYTHON_TAG,    PYTHON_ELEMENT, scr_state, src_cont)

