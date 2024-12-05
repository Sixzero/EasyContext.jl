export LLM_overview
 
LLM_overview(question; max_token, extra="") = begin
	# @show question
	# @show max_token
	# @show extra
	aigenerated = PromptingTools.aigenerate("""Create an summary of the quesiton and use maximum $(max_token) tokens for your answer. The fewer token you use the better! Try to be short catchy and slightly descriptive with the summary.
  $(extra)
	
	Only answer with the summary nothing else!
	
	The question that has to be summarized is:
	$(question)
	""", model="gem15f", verbose=false) # gpt4om
	return String(aigenerated.content)
end