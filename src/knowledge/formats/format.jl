
code_format(content::String, language::String="") = ""*
"""```$language
$content
```
"""

file_format(filepath::String, content::String, language::String="") = ""*
"""File: $filepath
$(code_format(content, language))
"""

email_format(to::String, subject::String, content::String) = ""*
"""<$(EMAIL_TAG) to=$to subject="$subject">
$content
</$(EMAIL_TAG)>
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

workspace_ctx_2_string(scr_state, src_cont) = to_string(WORKSPACE_TAG, WORKSPACE_ELEMENT, scr_state, src_cont) 
julia_ctx_2_string(scr_state, src_cont)     = to_string(JULIA_TAG,     JULIA_ELEMENT, scr_state, src_cont) 
python_ctx_2_string(scr_state, src_cont)    = to_string(PYTHON_TAG,    PYTHON_ELEMENT, scr_state, src_cont) 
