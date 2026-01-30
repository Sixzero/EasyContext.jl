using EasyContext

"""
This example demonstrates various ways to use FluidAgent for automation tasks.
"""

# 1. Basic file operations
function demo_file_operations(model="claude")
    println("\n=== File Operations Demo ===")
    
    agent = FluidAgent(
        tools=[LocalCreateFileTool, LocalModifyFileTool, CatFileTool],
        model=model,
        sys_msg=SysMessageV1(; sys_msg="You are a helpful assistant.")
    )

    # Create and modify files
    response = work(agent, """
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
function demo_shell_commands(model="claude")
    println("\n=== Shell Commands Demo ===")
    
    agent = FluidAgent(
        tools=[BashTool],
        model=model
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
function demo_complex_task(model="claude")
    println("\n=== Complex Task Demo ===")
    
    agent = FluidAgent(
        tools=[LocalCreateFileTool, LocalModifyFileTool, BashTool],
        model=model
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

# 4. Streaming demo
function demo_streaming(model="claude")
    println("\n=== Streaming Demo ===")
    
    agent = FluidAgent(
        tools=[LocalCreateFileTool, LocalModifyFileTool, BashTool],
        model=model
    )

    # Use streaming with syntax highlighting
    response = run(agent, """
        Create a small Julia script that:
        1. Defines a function to calculate fibonacci numbers
        2. Adds some test cases
        """;
        on_text = text -> print(text),
        on_error = err -> println("Error: ", err),
        on_done = () -> println("\nDone!")
    )

    println("\nFinal Results:")
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
    demo_streaming()
end

run_demos()
