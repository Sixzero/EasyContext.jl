using Crayons

# Check if Highlights is available at precompile time
const HIGHLIGHTS_AVAILABLE = Base.find_package("Highlights") !== nothing

@kwdef mutable struct SyntaxHighlightState
    io::IO = stdout
    buffer::IOBuffer = IOBuffer()
    in_code_block::Int = 0
    language::String = ""
    current_line::String = ""
end

@kwdef mutable struct PlainSyntaxState
    in_code_block::Int = 0
    current_line::String = ""
end

# Lexer handling - Highlights package API changed significantly
# Using tree-sitter based highlighting in new versions
if HIGHLIGHTS_AVAILABLE
    using Highlights

    # New Highlights API uses tree-sitter and doesn't have Lexers module
    # Just use the highlight function with language strings
    const lexer_map = Dict{String, String}(
        "jl" => "julia",
        "julia" => "julia",
        "py" => "python",
        "python" => "python",
        "js" => "javascript",
        "javascript" => "javascript",
        "ts" => "typescript",
        "typescript" => "typescript",
        "sh" => "bash",
        "bash" => "bash",
        "toml" => "toml",
        "json" => "json",
        "yaml" => "yaml",
        "yml" => "yaml",
        "md" => "markdown",
        "markdown" => "markdown",
    )

    get_lexer(language::AbstractString) = get(lexer_map, lowercase(language), "julia")

    function highlight_string(code::AbstractString, language::String)
        try
            sprint() do buf
                highlight(buf, MIME("text/ansi"), code, language)
            end
        catch
            # Fallback if language not supported
            code
        end
    end
else
    const lexer_map = Dict{String, Any}()
    get_lexer(language::AbstractString) = nothing
    highlight_string(code::AbstractString, lexer) = code
end

function process_buffer(state::SyntaxHighlightState; flushh::Bool=false)
    content = String(take!(state.buffer))
    isempty(content) && return

    if HIGHLIGHTS_AVAILABLE
        lexer = get_lexer(state.language)
        highlighted = highlight_string(content, lexer)
        print(state.io, highlighted)
    else
        print(state.io, content)
    end
    flush(state.io)
end

function handle_text(state::SyntaxHighlightState, text::AbstractString)
    for char in text
        if char == '\n'
            process_line(state)
            state.current_line = ""
        else
            state.current_line *= char
        end
    end
end

function is_opener_ticks(line::AbstractString, nesting_level::Int)
    if nesting_level == 0
        return startswith(line, "```")
    else
        return line !== "```$(END_OF_CODE_BLOCK)" && (startswith(line, "```") && length(strip(line)) > 3)
    end
end

function is_closer_ticks(line::AbstractString)
    return startswith(line, "```$(END_OF_CODE_BLOCK)") || (strip(line)=="```")
end

function process_line(state::SyntaxHighlightState)
    line = state.current_line
    if is_opener_ticks(line, state.in_code_block)
        handle_code_block_start(state, line)
    elseif is_closer_ticks(line)
        handle_code_block_end(state, line)
    elseif state.in_code_block > 0
        write(state.buffer, line, '\n')
        process_buffer(state)
    else
        println(state.io, line)
        flush(state.io)
    end
end

function handle_text(state::PlainSyntaxState, text::AbstractString)
    print(stdout, text)
end

function handle_code_block_start(state::SyntaxHighlightState, line::AbstractString)
    state.in_code_block += 1
    if state.in_code_block == 1
        state.language = length(line) > 3 ? strip(line[4:end]) : ""
        print(state.io, Crayon(background = (40, 44, 52)))
        print(state.io, "\e[K")
        println(state.io, "```$(state.language)")
        flush(state.io)
    else
        write(state.buffer, line, '\n')
    end
end

function handle_code_block_end(state::SyntaxHighlightState, line::AbstractString)
    if state.in_code_block > 0
        state.in_code_block -= 1
        if state.in_code_block == 0
            process_buffer(state, flushh=true)
            print(state.io, "```")
            print(state.io, Crayon(reset = true))
            println(state.io)
            flush(state.io)
        else
            write(state.buffer, line, '\n')
        end
    else
        println(state.io, line)
        flush(state.io)
    end
end
