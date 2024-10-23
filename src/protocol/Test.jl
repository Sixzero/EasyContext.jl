export TestFramework, add_tests

@kwdef mutable struct TestFramework
	test_cases::String="There are no test cases written for this conversation. If this problem is testable then test cases would be nice to have!"
end

add_tests(user_question, tf::TestFramework) = begin
	tf.test_cases=="" && return """$(user_question)
	Decide if the user question is testable and if it is so then try to write tests and run them after you provided a solution to make verify that you really solved the problem."""
	return """$(user_question)

	<$TESTS>
	You should use the test from this codeblock:
	``` 
	(tf.test_cases)
	```
	Also figure out how to you run the tests. 
	You can create or modify test files or do a single command that is able to verify that you solved the tests. Also make sure the tests are running correctly. 
	You should only modify the test if you want to extend or if you spot a mistake in the test. 
	</$TESTS>
	"""
end



