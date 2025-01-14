using Test
using EasyContext
using PromptingTools
using OrderedCollections

@testset "FluidAgent Tests" begin
    @testset "Basic Tool Execution" begin
        # Create agent with basic tools
        agent = FluidAgent(
            tools=(CreateFileTool, CatFileTool),
            model="gpt-4-1106-preview",  # or any available model
            workspace=mktempdir()
        )

        # Test file creation and reading
        mktempdir() do dir
            cd(dir) do
                response = run(agent, """Create a file called 'test.txt' with content "Hello World" and then read it back.""")
                
                # Check response structure
                @test response isa NamedTuple
                @test hasfield(typeof(response), :content)
                @test hasfield(typeof(response), :results)
                
                # Verify file was created
                @test isfile("test.txt")
                @test read("test.txt", String) == "Hello World\n"
                
                # Check results
                @test response.results isa OrderedDict
                @test !isempty(response.results)
            end
        end
    end

    @testset "Tool Preprocessing Order" begin
        # Create agent with tools that need preprocessing
        agent = FluidAgent(
            tools=(ModifyFileTool, CreateFileTool),
            model="gpt-4-1106-preview"
        )

        mktempdir() do dir
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
