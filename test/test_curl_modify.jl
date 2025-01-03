using Test
using EasyContext
using EasyContext: CodeBlock, codestr, execute_with_output
using JSON3
using HTTP

@testset "test curl modify command" begin
    # Test the curl command generation
    file_path = "/tmp/test.txt"
    content = "test content\nwith \"quotes\" and 'single quotes' yes."
    
    # Set editor to MELD_PRO
    EasyContext.CURRENT_EDITOR = EasyContext.MELD_PRO
    
    # Create a CodeBlock
    cb = CodeBlock(;
        type=:MODIFY, language="", file_path, content, root_path="/"
    )
    cb.postcontent = "Postporcessed: $(cb.content)" 

    # Get the command string
    cmd = codestr(cb)
    
    # Expected curl command pattern with proper escaping
    expected_pattern = r"""curl -X POST http://localhost:$DEFAULT_MELD_PORT/diff -H \\"Content-Type: application/json\\" -d '\{.*\\"leftPath\\".*\\"rightContent\\".*\}'"""
    
    @test occursin(expected_pattern, cmd)
    @test occursin(file_path, cmd)
    @test occursin("test content", cmd)

    # Test actual curl command execution with execute_with_output
    @testset "curl command execution" begin
        curl_cmd = `zsh -c $cmd`
        output = execute_with_output(curl_cmd)
        @show output
        
        # If server is running, we expect a JSON response
        if !occursin("Connection refused", output)
            try
                # Parse the output to find the JSON response
                json_start = findlast('{', output)
                json_end = findlast('}', output)
                if json_start !== nothing && json_end !== nothing
                    json_str = output[json_start:json_end]
                    response = JSON3.read(json_str)
                    @test haskey(response, "status")
                    @test response["status"] == "ok"
                    @test haskey(response, "id")
                end
            catch e
                @warn "Could not parse JSON response: $output"
            end
        else
            @warn "Diff server is not running on localhost:$DEFAULT_MELD_PORT"
        end
    end

end
;
