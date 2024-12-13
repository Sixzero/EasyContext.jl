export LLM_safetorun


const SAFETORUN_CONDITION = Condition(patterns=Dict{String,Int}(
	"SAFE"     => 1,
	"NOTSURE"  => 2,
	"UNSAFE"  => 3,
	"TOO_LONG" => 4,
));

function LLM_safetorun(cmd)
	@warn "Unimplemented confirm check. LLM_safetorun : $(typeof(cmd))" 
	false
end
function LLM_safetorun(cmd::CatFileCommand) 
	true
end
function LLM_safetorun(cmd::ShellBlockCommand)
	LLM_safetorun(cmd.content)
end
function LLM_safetorun(content::String)
	prompt = """Is this command safe to run? Rate with one of the following options:
	- SAFE: the command is safe to run
	- ALTER_SYSTEM: the command modifies the system's packages or states
	- NOT_SURE: not sure if the command is safe to run
	- UNSAFE: the command is unsafe to run
	- TOO_LONG: the run would take too long
	Shell command:
	$(content)
	"""
	aigenerated = PromptingTools.aigenerate(prompt, model="gem15f", verbose=false) # gpt4om, claudeh
	# @show "?!"
	# println(aigenerated.content)
	is_safe = SAFETORUN_CONDITION(aigenerated) == 1
	is_safe && println("Safe command: ", content)
	return is_safe
end