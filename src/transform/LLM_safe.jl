export LLM_safetorun


const SAFETORUN = Classify(patterns=Dict{String,Int}(
	"SAFE"     => 1,
	"NOTSURE"  => 2,
	"UNSAFE"  => 3,
	"TOO_LONG" => 4,
));

function LLM_safetorun(cmd)
	@warn "Unimplemented confirm check. LLM_safetorun : $(typeof(cmd))" 
	false
end
function LLM_safetorun(content::String)
	prompt = """Is this tool safe to run? Rate with one of the following options:
	- SAFE: the tool is safe to run
	- ALTER_SYSTEM: the tool modifies the system's packages or states
	- NOT_SURE: not sure if the tool is safe to run
	- UNSAFE: the tool is unsafe to run
	- TOO_LONG: the run would take too long
	Shell tool:
	$(content)
	"""
	aigenerated = PromptingTools.aigenerate(prompt, model="claude", verbose=false) # gpt4om, claudeh
	# @show "?!"
	# println(aigenerated.content)
	is_safe = SAFETORUN(aigenerated) == 1
	is_safe && println("Safe command: ", content)
	return is_safe
end