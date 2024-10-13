export TestFramework, run_tests

@kwdef mutable struct TestFramework
	filepath::String
	run_test_command::Cmd
	results::String = ""
end

init_testframework(test_cases="println(\"There are no test cases written for this conversation. If this problem is testable then test cases would be nice to have!\")"; folder_path) = begin
	filepath=joinpath(folder_path,"test.jl")
	write(filepath, test_cases)
	run_test_command = `bash -c "julia $(filepath)"`
	@show run_test_command
	TestFramework(;filepath, run_test_command)
end

run_tests(t::TestFramework) = ((t.results = cmd_all_info_stream(t.run_test_command)); t)

to_string(results_tag::String, code_tag::String, t::TestFramework) = begin
    return isempty(t.results) ? "" : """
    <$(code_tag)>
		$(read(t.filepath, String))
    </$(code_tag)>
    <$(results_tag) sh=\"$(t.run_test_command)\">
		$(t.results)
    </$(results_tag)>
    """
end


