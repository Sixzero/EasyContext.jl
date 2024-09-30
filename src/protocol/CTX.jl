
const Context = Dict{String, String}

(ctx::Context)(new_ctx::Context) = merge(ctx, new_ctx)

SHELL_TAG         = "ShellRunResults"
SHELL_ELEMENT     = "sh_script"
SHELL_RUN_RESULT  = "sh_run_result"
WORKSPACE_TAG     = "Codebase" 
WORKSPACE_ELEMENT = "File" 
JULIA_TAG         = "JuliaFunctions" 
JULIA_ELEMENT     = "Function" 
PYTHON_TAG        = "PythonPackages" 
PYTHON_ELEMENT    = "Package" 

shell_ctx_2_string(cb_extractor)            = to_string(SHELL_TAG,     SHELL_ELEMENT, cb_extractor) 
workspace_ctx_2_string(scr_state, src_cont) = to_string(WORKSPACE_TAG, WORKSPACE_ELEMENT, scr_state, src_cont) 
julia_ctx_2_string(scr_state, src_cont)     = to_string(JULIA_TAG,     JULIA_ELEMENT, scr_state, src_cont) 
python_ctx_2_string(scr_state, src_cont)    = to_string(PYTHON_TAG,    PYTHON_ELEMENT, scr_state, src_cont) 

workspace_format_description()  = "\
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, \
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags."
shell_format_description()      = "\
Shell command  will be included in the next user message \
wrapped in <$(SHELL_TAG)> and </$(SHELL_TAG)> tags, \
the perviously requested shell script (shortened just for readability) and is in <$(SHELL_ELEMENT)> and </$(SHELL_ELEMENT)> tags, the sh run output is in <sh_output> and </sh_output> tags."
julia_format_description()      = "\
The Julia function definitions in other existing installed packages will be in the user message and \
wrapped in <$(JULIA_TAG)> and </$(JULIA_TAG)> tags, \
with individual functions wrapped in <$(JULIA_ELEMENT)> and </$(JULIA_ELEMENT)> tags."
python_format_description()     = "\
The Python packages in other existing installed packages will be in the user message and \
wrapped in <$(PYTHON_TAG)> and </$(PYTHON_TAG)> tags, \
with individual chunks wrapped in <$(PYTHON_ELEMENT)> and </$(PYTHON_ELEMENT)> tags."




