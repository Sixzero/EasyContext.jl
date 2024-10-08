export TestFramework, run_tests

@kwdef mutable struct TestFramework
	filename::String
	run_test_command::Cmd
	results::String = ""
end

init_testframework(p::PersistableState, conv_ctx, test_cases="println(\"There are no test cases written for this conversation. If this problem is testable then test cases would be nice to have!\")", filepath="") = begin
	if isempty(filepath)
		filename = joinpath(CONVERSATION_DIR(p),conv_ctx.id) * ".jl"
		write(filename, test_cases)
	else
		filename=filepath
	end
	run_test_command = `bash -c "julia $(filename)"`
	@show run_test_command
	TestFramework(;filename, run_test_command)
end

run_tests(t::TestFramework) = ((t.results = cmd_all_info_stream(t.run_test_command)); t)

to_string(results_tag::String, code_tag::String, t::TestFramework) = begin
    return isempty(t.results) ? "" : """
    <$(code_tag)>
		$(read(t.filename, String))
    </$(code_tag)>
    <$(results_tag) sh=\"$(t.run_test_command)\">
		$(t.results)
    </$(results_tag)>
    """
end


