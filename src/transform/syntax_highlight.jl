using Highlights
using Highlights: AbstractLexer
using Crayons

@kwdef mutable struct SyntaxHighlightState
    io::IO = stdout
    buffer::IOBuffer = IOBuffer() # the buffer to sotre a line of string before applying printings
    in_code_block::Int = 0  # Now represents nesting level
    language::String = ""
    current_line::String = ""
end

@kwdef mutable struct PlainSyntaxState
    in_code_block::Int = 0  # Now represents nesting level
    current_line::String = ""
end

const lexer_map = Dict(
    "jl" => Lexers.JuliaLexer,
    "julia" => Lexers.JuliaLexer,
    "matlab" => Lexers.MatlabLexer,
    "r" => Lexers.RLexer,
    "fortran" => Lexers.FortranLexer,
    "toml" => Lexers.TOMLLexer,
    # Work in progress lexers:
    # "py" => Lexers.PythonLexer,
    # "python" => Lexers.PythonLexer,
    # "sh" => Lexers.BashLexer,
    # "bash" => Lexers.BashLexer,
    # "zsh" => Lexers.BashLexer,
    # "cpp" => Lexers.CPPLexer,
    # "c++" => Lexers.CPPLexer,
    # "js" => Lexers.JavaScriptLexer,
    # "javascript" => Lexers.JavaScriptLexer,
)

get_lexer(language::AbstractString) = get(lexer_map, lowercase(language), Lexers.JuliaLexer)

function process_buffer(state::SyntaxHighlightState; flushh::Bool=false)
    content = String(take!(state.buffer))
    isempty(content) && return
    
    lexer = get_lexer(state.language)
    highlighted = highlight_string(content, lexer)
    print(state.io, highlighted)
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
    print(stdout, text)  # Use stdout as default
end

function handle_code_block_start(state::SyntaxHighlightState, line::AbstractString)
    state.in_code_block += 1
    if state.in_code_block == 1
        state.language = length(line) > 3 ? strip(line[4:end]) : ""
        print(state.io, Crayon(background = (40, 44, 52)))  # Set background
        print(state.io, "\e[K")  # Clear to end of line with current background color
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
            print(state.io, Crayon(reset = true))  # Reset codeblock bg
            println(state.io)  # Now the newline is not colored
            flush(state.io)
        else
            write(state.buffer, line, '\n')
        end
    else
        println(state.io, line)  # Unmatched closing ticks, just print it
        flush(state.io)
    end
end

highlight_string(code::AbstractString, lexer::Type{<:AbstractLexer}) = sprint() do buf
    highlight(buf, MIME("text/ansi"), code, lexer)
end

function Highlights.Format.render(io::IO, ::MIME"text/ansi", tokens::Highlights.Format.TokenIterator)
    for (str, id, style) in tokens
        cg = Crayon(
            foreground = style.fg.active ? (style.fg.r, style.fg.g, style.fg.b) : nothing,
            background = style.bg.active ? (style.bg.r, style.bg.g, style.bg.b) : nothing,
            bold = style.bold,
            italics = style.italic,
            underline = style.underline
        )
        print(io, cg, str, inv(cg))
        flush(io)
    end
end

