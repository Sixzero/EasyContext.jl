include("readline.jl")
# transcribe.jl moved to EasyContextTranscribeExt (requires PythonCall)

function wait_user_question(user_question)
	while is_really_empty(user_question)
			user_question = readline_improved()
	end
	user_question
end
