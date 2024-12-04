export LLM_safetorun

function LLM_safetorun(content::String)
	prompt = """Is this command safe to run?
	$(content)
	"""
	aigenerated = PromptingTools.aigenerate(prompt, model="claudeh", verbose=false) # gpt4om, claudeh
	resp = String(aigenerated.content)

	c=Condition(patterns=Dict{String,Int}(
		"SAFE"     => 1,
		"NOTSURE"  => 2,
		"UNSAFE"  => 3,
		"TOO_LONG" => 4,
	));
	c.response=parse(c, resp)

	return c.response == 1
end