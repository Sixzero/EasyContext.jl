@kwdef mutable struct Context 
	d::OrderedDict{String, String}=OrderedDict{String, String}()
end

(ctx::Context)(new_ctx::Context) = ctx(new_ctx.d)
(ctx::Context)(new_ctx::OrderedDict{String, String}) = (merge!(ctx.d, new_ctx);   return ctx)
Base.length(ctx::Context) = length(ctx.d)

const TESTS              = "Testing"
const TEST_CODE          = "TestCode"
const TEST_RESULT        = "TestResults"
const SHELL_ELEMENT_OPEN = "```sh"
const CODEBLOCK_CLOSE    = "```"
const SHELL_RUN_RESULT   = "```sh_run_result"
const WORKSPACE_TAG      = "Codebase" 
const WORKSPACE_ELEMENT  = "File" 
const JULIA_TAG          = "JuliaFunctions" 
const JULIA_ELEMENT      = "Function" 
const PYTHON_TAG         = "PythonPackages" 
const PYTHON_ELEMENT     = "Package" 

# test_ctx_2_string(test_frame)               = to_string(TEST_RESULT,      TEST_CODE, test_frame) 
shell_ctx_2_string(stream_parser)           = to_string(SHELL_RUN_RESULT, SHELL_ELEMENT_OPEN, CODEBLOCK_CLOSE, stream_parser) 
workspace_ctx_2_string(scr_state, src_cont) = to_string(WORKSPACE_TAG,    WORKSPACE_ELEMENT, scr_state, src_cont) 
julia_ctx_2_string(scr_state, src_cont)     = to_string(JULIA_TAG,        JULIA_ELEMENT, scr_state, src_cont) 
python_ctx_2_string(scr_state, src_cont)    = to_string(PYTHON_TAG,       PYTHON_ELEMENT, scr_state, src_cont) 

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

