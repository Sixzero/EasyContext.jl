export LLM_summary



function LLM_summary(path::String, content::String)
	prompt = """Summarize the following file for yourself in a very concise way (don't name the file and say it is a file, we know which file it is. So just describe it) to be able to know what it does and what it contains:
	$(file_format(path, content))
	"""
	aigenerated = PromptingTools.aigenerate(prompt, model="gem15f", verbose=false) # gpt4om, claudeh
	# println(path)
	# println(aigenerated.content)
	return String(aigenerated.content)
end