using EasyContext
using EasyContext: EXPLORE_TAG
using ToolCallFormat: ParsedCall, ParsedValue, create_tool, execute, result2string
using OpenRouterCLIProxyAPI

setup_cli_proxy!(mutate=true)

sub_tools = [
    ToolGenerator(CatFileTool, (root_path=pwd(),)),
    ToolGenerator(BashTool, (root_path=pwd(), no_confirm=true, io=devnull)),
]

explore = ExploreTool(tools=sub_tools)

# Simulate what the LLM would do: create a tool call with a query
call = ParsedCall(name=EXPLORE_TAG, kwargs=Dict("query" => ParsedValue(value="Explore this codebase ($(pwd())). Answer: How is the system prompt built? What functions does the `work()` call chain invoke? Read the key files and summarize.")))
tool = create_tool(explore, call)

execute(tool, SimpleContext())
println(result2string(tool))
