
code_format(content::String, language::String="") = ""*
"""```$language
$content
```"""

file_format(filepath::String, content::String, language::String="") = ""*
"""File: $filepath
$(code_format(content, language))
"""

email_format(to::String, subject::String, content::String) = ""*
"""$(EMAIL_TAG) to=$to subject="$subject"
$content
$(END_OF_BLOCK_TAG)
"""


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

