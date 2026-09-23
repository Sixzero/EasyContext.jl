using EasyContext
using EasyContext: explore_sys_prompt
using OpenRouterCLIProxyAPI

setup_cli_proxy!(mutate=true)

# --- Create explore agent (native tool calling, read-only tools) ---
model = "openai:openai/gpt-6-luna"

tools = [
    ToolGenerator(CatFileTool, (root_path=pwd(),)),
    ToolGenerator(BashTool, (root_path=pwd(), no_confirm=true)),
]

agent = create_FluidAgent(model;
    tools,
    extractor_type=NativeExtractor,
    sys_msg=explore_sys_prompt(tools),
)


# --- Run exploration task ---
task = "Explore this codebase ($(pwd())). Answer: How is the system prompt built? What functions does the `work()` call chain invoke? Read the key files and summarize."

println("=== Starting explore agent ===")
println("Task: $task\n")

response = work(agent, task; io=stdout, quiet=true)

println("\n=== Agent response ===")
println(response.content)
