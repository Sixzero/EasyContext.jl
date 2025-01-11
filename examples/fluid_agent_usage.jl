using EasyContext
using PromptingTools

"""
This example demonstrates various ways to use FluidAgent for automation tasks.
"""

# 1. Basic file operations
function demo_file_operations()
    println("\n=== File Operations Demo ===")
    
    agent = FluidAgent(
        tools=(CreateFileTool, ModifyFileTool, CatFileTool),
        model="claude"
    )

    # Create and modify files
    response = run(agent, """
        1. Create a config.json file with basic settings
        2. Then modify it to add more settings
        3. Show me the final content
    """)

    println("\nAgent Response:")
    println(response.content)
    println("\nTool Results:")
    for (id, result) in response.results
        println("- ", result)
    end
end

# 2. Shell command execution
function demo_shell_commands()
    println("\n=== Shell Commands Demo ===")
    
    agent = FluidAgent(
        tools=(ShellBlockTool,),
        model="claude"
    )

    # Execute some shell commands
    response = run(agent, """
        Show me:
        1. Current directory contents
        2. System information
    """)

    println("\nAgent Response:")
    println(response.content)
end

# 3. Multi-step task automation
function demo_complex_task()
    println("\n=== Complex Task Demo ===")
    
    agent = FluidAgent(
        tools=(CreateFileTool, ModifyFileTool, ShellBlockTool),
        model="claude"
    )

    # Complex multi-step task
    response = run(agent, """
        Create a small Python project:
        1. Create a main.py with a simple "Hello World" function
        2. Create a test.py file to test the main function
        3. Run the test
    """)

    println("\nAgent Response:")
    println(response.content)
    println("\nTool Results:")
    for (id, result) in response.results
        println("- ", result)
    end
end

# Run demos
function run_demos()
    println("FluidAgent Usage Examples")
    println("========================")
    
    demo_file_operations()
    demo_shell_commands()
    demo_complex_task()
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_demos()
end
