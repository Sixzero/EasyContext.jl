code_format(content::String, language::String="") = ""*
"""```$language
$content
```$(END_OF_CODE_BLOCK)"""

raw_format(content::String) = """```
$content
```"""

file_format(filepath::String, content::String, language::String="") = ""*
"""File: $filepath
$(code_format(content, language))
"""

source_format(tag::String, filepath::String, content::String) = """$tag $filepath
$(raw_format(content))"""


email_format(to::String, subject::String, content::String) = ""*
"""$(EMAIL_TAG) to=$to subject="$subject"
$content
$(END_OF_BLOCK_TAG)
"""

function parse_code_block(content::String)
	lines = split(content, '\n')
	first_line = first(lines)
	
	if startswith(first_line, "```")
			language = length(first_line) > 3 ? first_line[4:end] : "sh"
			content = join(lines[2:end-1], '\n')
			return language, content
	end
	
	return "sh", content
end

function parse_raw_block(content::String)
	lines = split(content, '\n')
	if startswith(first(lines), "```")
		return join(lines[2:end-1], '\n')
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

workspace_ctx_2_string(ctx_codebase)        = workspace_ctx_2_string(ctx_codebase[1], ctx_codebase[2])
workspace_ctx_2_string(scr_state, src_cont) = serialize(WORKSPACE_TAG, WORKSPACE_ELEMENT, scr_state, src_cont)
julia_ctx_2_string(ctx_julia)               = julia_ctx_2_string(ctx_julia[1], ctx_julia[2])
julia_ctx_2_string(scr_state, src_cont)     = serialize(JULIA_TAG,     JULIA_ELEMENT, scr_state, src_cont)
python_ctx_2_string(ctx_python)             = python_ctx_2_string(ctx_python[1], ctx_python[2])
python_ctx_2_string(scr_state, src_cont)    = serialize(PYTHON_TAG,    PYTHON_ELEMENT, scr_state, src_cont)

