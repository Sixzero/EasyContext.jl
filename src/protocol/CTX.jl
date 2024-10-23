@kwdef mutable struct Context 
	d::OrderedDict{String, String}=OrderedDict{String, String}()
end

(ctx::Context)(new_ctx::Context) = ctx(new_ctx.d)
(ctx::Context)(new_ctx::OrderedDict{String, String}) = (merge!(ctx.d, new_ctx);   return ctx)
Base.length(ctx::Context) = length(ctx.d)

const TESTS             = "Testing"
const TEST_CODE         = "TestCode"
const TEST_RESULT       = "TestResults"
const SHELL_TAG         = "ShellRunResults"
const SHELL_ELEMENT     = "sh_script"
const SHELL_RUN_RESULT  = "sh_run_result"
const WORKSPACE_TAG     = "Codebase" 
const WORKSPACE_ELEMENT = "File" 
const JULIA_TAG         = "JuliaFunctions" 
const JULIA_ELEMENT     = "Function" 
const PYTHON_TAG        = "PythonPackages" 
const PYTHON_ELEMENT    = "Package" 

test_ctx_2_string(test_frame)               = to_string(TEST_RESULT,     TEST_CODE, test_frame) 
shell_ctx_2_string(cb_extractor)            = to_string(SHELL_TAG,     SHELL_ELEMENT, cb_extractor) 
workspace_ctx_2_string(scr_state, src_cont) = to_string(WORKSPACE_TAG, WORKSPACE_ELEMENT, scr_state, src_cont) 
julia_ctx_2_string(scr_state, src_cont)     = to_string(JULIA_TAG,     JULIA_ELEMENT, scr_state, src_cont) 
python_ctx_2_string(scr_state, src_cont)    = to_string(PYTHON_TAG,    PYTHON_ELEMENT, scr_state, src_cont) 

workspace_format_description()  = "\
The codebase you are working on will be wrapped in <$(WORKSPACE_TAG)> and </$(WORKSPACE_TAG)> tags, \
with individual files chunks wrapped in <$(WORKSPACE_ELEMENT)> and </$(WORKSPACE_ELEMENT)> tags."
virtual_workspace_description(vws)  = "\
You have a folder where you can create file and store things: $(vws.rel_path)"
shell_format_description()      = "\
Shell command  will be included in the next user message \
wrapped in <$(SHELL_TAG)> and </$(SHELL_TAG)> tags, \
the perviously requested shell script (shortened just for readability) and is in <$(SHELL_ELEMENT)> and </$(SHELL_ELEMENT)> tags, the sh run output is in <$(SHELL_RUN_RESULT)> and </$(SHELL_RUN_RESULT)> tags."
julia_format_description()      = "\
The Julia function definitions in other existing installed packages will be in the user message and \
wrapped in <$(JULIA_TAG)> and </$(JULIA_TAG)> tags, \
with individual functions wrapped in <$(JULIA_ELEMENT)> and </$(JULIA_ELEMENT)> tags."
python_format_description()     = "\
The Python packages in other existing installed packages will be in the user message and \
wrapped in <$(PYTHON_TAG)> and </$(PYTHON_TAG)> tags, \
with individual chunks wrapped in <$(PYTHON_ELEMENT)> and </$(PYTHON_ELEMENT)> tags."
# test_format_description(t)      = """
# We have a buildin testframework which has a testfile: $(t.filepath) 
# We run the test file: $(t.run_test_command) 
# To create tests that runs automatically, you have to modify the testfile: $(t.filepath) 
# The test code is wrapped in <$(TEST_CODE)> and </$(TEST_CODE)> tags, 
# Each run results of test_code run is wrapped in <$(TEST_RESULT) sh="$(t.run_test_command)"> and </$(TEST_RESULT)> tags where the sh property is the way we run the test file.
# """


# If you find the default test run command not appropriate then you can propose another one like: 

