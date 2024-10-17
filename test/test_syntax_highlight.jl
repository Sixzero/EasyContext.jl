using Test
using EasyContext
using EasyContext: SyntaxHighlightState, PlainSyntaxState, handle_text, process_buffer

@testset "SyntaxHighlight Tests" begin
    @testset "Non-codeblock text" begin
        state = SyntaxHighlightState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "This is some non-codeblock text.\n")
            handle_text(state, "It should not be highlighted.\n")
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test result == "This is some non-codeblock text.\nIt should not be highlighted.\n"
        @test state.in_code_block == 0
    end

    @testset "Simple codeblock" begin
        state = SyntaxHighlightState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "```julia\n")
            handle_text(state, "function hello()\n")
            handle_text(state, "    println(\"Hello, World!\")\n")
            handle_text(state, "end\n")
            handle_text(state, "```\n")
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test occursin("```julia", result)
        @test occursin("\e[38;2;148;91;176;1;23;24mfunction\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24mhello", result)
        @test occursin("println\e[39m\e[22;23;24m(\e[38;2;201;61;57;22;23;24m\"Hello, World!\"", result)
        @test occursin("end", result)
        @test occursin("```", result)
        @test state.in_code_block == 0
    end

    @testset "Mixed content" begin
        state = SyntaxHighlightState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "Here's a simple\nJulia function:\n")
            handle_text(state, "```\n")
            handle_text(state, "function greet(name)\n")
            handle_text(state, "    println(\"Hello, \$name!\")\n")
            handle_text(state, "end\n")
            handle_text(state, "```\n")
            process_buffer(state, flush=true)
            handle_text(state, "That was a code block.\n")
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test startswith(result, "Here's a simple\n")
        @test occursin("Julia function:\n", result)
        @test occursin("```", result)
        @test occursin("greet\e[39m\e[22;23;24m(\e[22;23;24mname", result)
        @test occursin("[38;2;66;102;213;22;23;24mprintln\e[39m\e[22;23;24m(\e[38;2;201;61;57;22;23;24m\"Hello, \e[39m\e[22;23;24m\$name!\e[38;2;201;61;57;22;23;24m\"", result)
        @test occursin("end", result)
        @test occursin("```", result)
        @test endswith(result, "That was a code block.\n")
        @test state.in_code_block == 0
    end

    @testset "PlainSyntaxState" begin
        state = PlainSyntaxState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "Here's a simple Julia function:\n")
            handle_text(state, "```julia\n")
            handle_text(state, "function greet(name)\n")
            handle_text(state, "    println(\"Hello, \$name!\")\n")
            handle_text(state, "end\n")
            handle_text(state, "```\n")
            handle_text(state, "That was a code block.\n")
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test result == "Here's a simple Julia function:\n```julia\nfunction greet(name)\n    println(\"Hello, \$name!\")\nend\n```\nThat was a code block.\n"
        @test state.in_code_block == 0
    end

    @testset "Complex Julia syntax" begin
        state = SyntaxHighlightState()
        
        complex_code = """
        @macro_example begin
            struct ComplexType{T<:Number}
                x::T
                y::T
            end

            function (obj::ComplexType)(z::Number)
                return obj.x * z + obj.y
            end

            [x^2 for x in 1:10 if iseven(x)]
        end
        """

        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "```julia\n")
            handle_text(state, complex_code)
            handle_text(state, "```\n")
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test occursin("```julia", result)
        @test occursin("@macro_example", result)
        @test occursin("struct\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24mComplexType", result)
        # @test occursin("function (obj::ComplexType)(z::Number)", result)
        
        # Check for color codes in the list comprehension
        # @test occursin(r"\[x\^2 for x in \e\[38;2;\d+;\d+;\d+(?:;1)?;23;24m1\e\[39m(?:;\\e22)?:\e\[38;2;\d+;\d+;\d+(?:;1)?;23;24m10\e\[39m(?:;\\e22)? if \e\[38;2;\d+;\d+;\d+(?:;1)?;23;24miseven\e\[39m(?:;22)?\(x\)\]", result)
        
        @test state.in_code_block == 0
        
        # Check for color codes (ANSI escape sequences)
        @test occursin("\e[", result)
        
        # Check for specific syntax highlighting
        @test occursin("\e[38;2;148;91;176;1;23;24mstruct\e[39;22m", result)
        @test occursin("\e[38;2;148;91;176;1;23;24mfunction\e[39;22m", result)
        @test occursin("\e[38;2;66;102;213;22;23;24miseven\e[39m\e[22", result)
    end

    @testset "Nested code blocks in docstrings" begin
        state = SyntaxHighlightState()
        
        nested_code = """
        \"\"\"
        Example function with nested code block:

        ```julia
        function nested_example()
            println("I'm nested!")
        end
        ```
        \"\"\"
        function outer_function()
            # Function body
        end
        """

        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "```julia\n")
            handle_text(state, nested_code)
            handle_text(state, "```\n")
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        # @test occursin("Example function with nested code block:", result)
        @test occursin("```julia", result)
        @test occursin("function nested_example()", result)
        @test occursin("function\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24mouter_function", result)
        @test state.in_code_block == 0
    end

    @testset "Word-by-word input" begin
        state = SyntaxHighlightState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "```")
            handle_text(state, "julia")
            handle_text(state, "\n")
            handle_text(state, "function")
            handle_text(state, " ")
            handle_text(state, "word_by_word")
            handle_text(state, "(")
            handle_text(state, ")")
            handle_text(state, "\n")
            handle_text(state, "    ")
            handle_text(state, "println")
            handle_text(state, "(")
            handle_text(state, "\"")
            handle_text(state, "Hello")
            handle_text(state, ",")
            handle_text(state, " ")
            handle_text(state, "World")
            handle_text(state, "!")
            handle_text(state, "\"")
            handle_text(state, ")")
            handle_text(state, "\n")
            handle_text(state, "end")
            handle_text(state, "\n")
            handle_text(state, "```")
            handle_text(state, "\n")
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test occursin("```julia", result)
        @test occursin("\e[38;2;148;91;176;1;23;24mfunction\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24mword_by_word", result)
        @test occursin("println\e[39m\e[22;23;24m(\e[38;2;201;61;57;22;23;24m\"Hello, World!\"", result)
        @test occursin("end", result)
        @test occursin("```", result)
        @test state.in_code_block == 0
    end

    @testset "Codeblock not at start of line" begin
        state = SyntaxHighlightState()
        
        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, "This is some text with a codeblock: ")
            handle_text(state, "```")
            handle_text(state, "julia")
            handle_text(state, "\n")
            handle_text(state, "function inline_codeblock()\n")
            handle_text(state, "    return \"I'm in an inline codeblock!\"\n")
            handle_text(state, "end ```")
            handle_text(state, "\n")
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test startswith(result, "This is some text with a codeblock: ")
        @test occursin("```julia", result)
        @test !occursin("\e[38;2;148;91;176;1;23;24mfunction\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24minline_codeblock", result)
        @test !occursin("\e[38;2;201;61;57;22;23;24m\"I'm in an inline codeblock!\"", result)
        @test occursin("end", result)
        @test occursin("```", result)
        @test state.in_code_block == 0
    end

    @testset "Nested codeblocks" begin
        state = SyntaxHighlightState()
        
        nested_code = """
        ```julia
        \"\"\"
        Example function with nested code block:

        ```julia
        function nested_example()
            println("I'm nested!")
        end
        ```
        \"\"\"
        function outer_function()
            # Function body
        end
        ```
        """

        pipe = Pipe()
        redirect_stdout(pipe) do
            handle_text(state, nested_code)
            process_buffer(state, flush=true)
        end
        close(pipe.in)
        
        result = String(read(pipe.out))
        @test occursin("```julia", result)
        # @test occursin("Example function with nested code block:", result)
        @test occursin("```julia", result)
        @test occursin("function nested_example()", result)
        # @test occursin("println(\"I'm nested!\")", result)
        @test occursin("function\e[39;22m\e[22;23;24m \e[38;2;66;102;213;22;23;24mouter_function", result)
        @test occursin("```", result)
        @test state.in_code_block==0
    end
end
#%%

state = SyntaxHighlightState()
        
        nested_code = """
        \"\"\"
        Example function with nested code block:

        ```julia
        function nested_example()
            println("I'm nested!")
        end
        ```
        \"\"\"
        function outer_function()
            # Function body
        end
        """

handle_text(state, "```julia\n")
handle_text(state, nested_code)
handle_text(state, "```\n")
process_buffer(state, flush=true)
#%%
state = SyntaxHighlightState()
        
nested_code = """
```julia
\"\"\"
Example function with nested code block:

```julia
function nested_example()
    println("I'm nested!")
end
```
\"\"\"
function outer_function()
    # Function body
end
```
"""

handle_text(state, nested_code)
process_buffer(state, flush=true)

#%%
state = SyntaxHighlightState()
        
complex_code = """
@macro_example begin
    struct ComplexType{T<:Number}
        x::T
        y::T
    end

    function (obj::ComplexType)(z::Number)
        return obj.x * z + obj.y
    end

    [x^2 for x in 1:10 if iseven(x)]
end
"""

handle_text(state, "```julia\n")
handle_text(state, complex_code)
handle_text(state, "```\n")
process_buffer(state, flush=true)
