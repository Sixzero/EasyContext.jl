using EasyContext
using EasyContext: opencode_gemini_understand_prompt
using OpenRouterCLIProxyAPI

setup_cli_proxy!(mutate=true)

# --- Create explore agent (native tool calling, read-only tools) ---
model = "anthropic:anthropic/claude-haiku-4.5"
explore_prompt = """You are a codebase exploration agent. Read files, run non-destructive shell commands (ls, grep, find, tree), and report findings.

$(opencode_gemini_understand_prompt)

IMPORTANT: Do NOT modify any files. Only read and inspect.
If a tool fails 3 times, stop retrying and report that the tools are faulty."""

tools = [
    ToolGenerator(CatFileTool, (root_path=pwd(),)),
    ToolGenerator(BashTool, (root_path=pwd(), no_confirm=true)),
]

agent = create_FluidAgent(model;
    tools,
    extractor_type=NativeExtractor,
    sys_msg=explore_prompt,
)


# --- Run exploration task ---
task = "Explore this codebase ($(pwd())). Answer: How is the system prompt built? What functions does the `work()` call chain invoke? Read the key files and summarize."

println("=== Starting explore agent ===")
println("Task: $task\n")

response = work(agent, task; io=stdout, quiet=true)

println("\n=== Agent response ===")
println(response.content)
