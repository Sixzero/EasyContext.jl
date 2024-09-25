





function context_combiner!(user_question, context_shell, context_codebase)
	"""
	$(context_shell)

	$(context_codebase)

	<Question>
	$(user_question)
	</Question>
	"""
end