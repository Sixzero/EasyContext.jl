using Test
using EasyContext
using PromptingTools
using EasyContext: Session, UserMessage, AIMessage, push_message!
using EasyContext: get_tool_results_agent, extract_tool_calls, pickStreamCallbackforIO
using OpenRouter: HttpStreamHooks
using UUIDs

@testset failfast=true "FluidAgent Tests" begin
    @testset "Agent Work Costs" begin
        # Create a custom IO type to track costs
        mutable struct CostTrackingIO <: IO
            costs::Ref{Float64}
            wrapped_io::IO
            
            CostTrackingIO(io::IO=devnull) = new(Ref(0.0), io)
        end
        
        # Implement required IO methods by forwarding to wrapped IO
        Base.write(io::CostTrackingIO, x::UInt8) = write(io.wrapped_io, x)
        Base.close(io::CostTrackingIO) = close(io.wrapped_io)
        
        # Override pickStreamCallbackforIO for our custom IO type
        function EasyContext.pickStreamCallbackforIO(io::CostTrackingIO)
            function create_cost_tracking_callback(config)
                return HttpStreamHooks(
                    content_formatter = config.on_content,
                    on_meta_usr = (tokens, cost, elapsed) -> nothing,
                    on_meta_ai = (tokens, cost, elapsed) -> nothing,
                    on_start = config.on_start,
                    on_done = config.on_done,
                    on_error = config.on_error,
                    on_stop_sequence = _ -> nothing,
                    on_cost = cost -> (io.costs[] += cost)
                )
            end
            return create_cost_tracking_callback
        end
        
        # Create our cost tracking IO
        cost_tracking_io = CostTrackingIO()
        
        # Create agent with basic tools
        agent = FluidAgent(
            tools=[CatFileTool, ShellBlockTool],
            model="gem20f",
            workspace=pwd(),
            sys_msg="You are a helpful assistant."
        )
        
        # Create a session
        session = Session()
        push_message!(session, UserMessage("List the current directory"))
        
        # Mock the aigenerate function to return a response with cost info
        original_aigenerate = PromptingTools.aigenerate
        
        try
            # Replace aigenerate with our mock version
            PromptingTools.aigenerate = function(messages; model, cache, api_kwargs, streamcallback, verbose)
                # Simulate cost tracking by calling the callback's on_cost
                streamcallback.on_cost(0.0015)
                
                # Create a mock response with cost information
                return (;
                    content = "I'll help you list the directory contents:\n\nBASH\n```sh\nls -la\n```endblock",
                    usage = (;
                        prompt_tokens = 100,
                        completion_tokens = 50,
                        total_tokens = 150
                    ),
                    cost = 0.0015,  # Mock cost
                    results = OrderedDict{UUID,String}(),
                    run_info = nothing
                )
            end
            
            # Call work function with our cost tracking IO
            work(agent, session; cache=false, no_confirm=true, io=cost_tracking_io)
            
            # Test that cost is tracked
            @test cost_tracking_io.costs[] > 0
            @test cost_tracking_io.costs[] ≈ 0.0015
            
        finally
            # Restore original function
            PromptingTools.aigenerate = original_aigenerate
        end
    end
    
    @testset "Basic Tool Execution" begin
        mktempdir() do dir
            # Create agent with basic tools
            agent = FluidAgent(
                tools=[LocalCreateFileTool, CatFileTool, ShellBlockTool],
                model="gem20f",  # or any available model
                workspace=dir,
                sys_msg="You are a helpful assistant."  # Add a simple system message
            )

            cd(dir) do
                # Create a session
                session = Session()
                push_message!(session, UserMessage("""
                1. Create a file called 'test.txt' with content "Hello World"
                2. List directory contents
                """))
                
                # Create a mock response instead of calling the API
                # This simulates what the LLM would return
                mock_content = """
                I'll help you create a file and list the directory contents.

                First, let's create the file:

                WRITE test.txt
                ```
                Hello World
                ```endblock

                Now, let's list the directory contents:

                BASH
                ```sh
                ls -la
                ```endblock
                """
                
                extract = agent.extractor_type(agent.tools)
                # Extract and execute tools directly
                extract_tool_calls(mock_content, extract, devnull; is_flush=true)
                execute_tools(extract; no_confirm=true)
                
                # Verify file was created
                @test isfile("test.txt")
                @test read("test.txt", String) == "Hello World\n"
                
                # Check results
                @test !isempty(get_tool_results_agent(extract.tool_tasks))
            end
        end
    end

    @testset "Tool Preprocessing Order" begin
        mktempdir() do dir
            # Create agent with tools that need preprocessing
            agent = FluidAgent(
                tools=[LocalModifyFileTool, LocalCreateFileTool],
                model="gem20f",
                workspace=dir,
                sys_msg="You are a helpful assistant."  # Add a simple system message
            )

            cd(dir) do
                # Create a session
                session = Session()
                push_message!(session, UserMessage("""
                Create two files:
                1. First create 'file1.txt' with content "Original"
                2. Then modify 'file1.txt' to say "Modified"
                """))
                
                # Create a mock response instead of calling the API
                # This simulates what the LLM would return
                mock_content = """
                I'll help you create and modify the file.

                First, let's create the file:

                WRITE file1.txt
                ```
                Original
                ```endblock

                Now, let's modify it:

                UPDATE file1.txt
                ```
                Modified
                ```endblock
                """
                
                extractor = agent.extractor_type(agent.tools)
                # Extract and execute tools directly
                extract_tool_calls(mock_content, extractor, devnull; is_flush=true)
                execute_tools(extractor; no_confirm=true)
                
                # Verify execution order
                @test isfile("file1.txt")
                @test read("file1.txt", String) == "Modified\n"
                @test !isempty(get_tool_results_agent(extractor.tool_tasks))
            end
        end
    end

    @testset "Error Handling" begin
        mktempdir() do dir
            # Create agent with potentially failing tools
            agent = FluidAgent(
                tools=[CatFileTool],
                model="gem20f",
                workspace=dir,
                sys_msg="You are a helpful assistant."  # Add a simple system message
            )

            cd(dir) do
                # Create a session
                session = Session()
                push_message!(session, UserMessage("Read the content of non_existent.txt"))
                
                # Create a mock response instead of calling the API
                # This simulates what the LLM would return
                mock_content = """
                I'll try to read the content of that file:

                READ non_existent.txt
                """
                
                extractor = agent.extractor_type(agent.tools)
                # Extract and execute tools directly
                extract_tool_calls(mock_content, extractor, devnull; is_flush=true)
                execute_tools(extractor; no_confirm=true)
                
                # Check error handling
                @test !isempty(get_tool_results_agent(extractor.tool_tasks))
                # Check if any tool result contains "No such file"
                @test occursin("No such file", get_tool_results_agent(extractor.tool_tasks))
            end
        end
    end
end
