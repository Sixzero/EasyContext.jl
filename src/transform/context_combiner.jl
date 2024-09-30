





function context_combiner!(user_question, contexts...)
	"""
	$(join(contexts, "\n"))
	<Question>
	$user_question
	</Question>
	"""
end