using Test
using EasyContext
using PromptingTools

@testset "FluidAgent Tests" begin
    @testset "Basic Tool Execution" begin
        mktempdir() do dir
            # Create agent with basic tools
            agent = FluidAgent(
                tools=(CreateFileTool, CatFileTool, ShellBlockTool),
                model="gpt-4-1106-preview",  # or any available model
                workspace=dir
            )

            cd(dir) do
                response = run(agent, """
                1. Create a file called 'test.txt' with content "Hello World"
                2. List directory contents
                """)
                
                # Check response structure
                @test response.content isa String
                @test hasfield(typeof(response), :run_info)
                @test hasfield(typeof(response), :results)
                @test hasfield(typeof(response), :shell_results)
                
                # Verify file was created
                @test isfile("test.txt")
                @test read("test.txt", String) == "Hello World\n"
                
                # Check results
                @test !isempty(response.results)
                @test !isempty(response.shell_results)  # Should have ls output
            end
        end
    end

    @testset "Tool Preprocessing Order" begin
        mktempdir() do dir
            # Create agent with tools that need preprocessing
            agent = FluidAgent(
                tools=(ModifyFileTool, CreateFileTool),
                model="gpt-4-1106-preview",
                workspace=dir
            )

            cd(dir) do
                # Create two files with modifications
                response = run(agent, """
                Create two files:
                1. First create 'file1.txt' with content "Original"
                2. Then modify 'file1.txt' to say "Modified"
                """)

                # Verify execution order
                @test isfile("file1.txt")
                @test read("file1.txt", String) == "Modified\n"
                @test !isempty(response.results)
            end
        end
    end

    @testset "Error Handling" begin
        # Create agent with potentially failing tools
        agent = FluidAgent(
            tools=(CatFileTool,),
            model="gpt-4-1106-preview"
        )

        response = run(agent, "Read the content of non_existent.txt")
        
        # Check error handling
        @test !isempty(response.results)
        @test any(contains(v, "No such file") for (_, v) in response.results)
    end
end
