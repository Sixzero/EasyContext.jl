export print_tool_result

abstract type AbstractTag end

@kwdef mutable struct ToolTag <: AbstractTag
    name::String
    content::String = ""
    args::String = ""
    kwargs::AbstractDict = Dict{String,String}()
end

# Convert raw ToolTag to specific tool types
function convert_tool(tag::ToolTag)
    return instantiate(Val(Symbol(tag.name)), tag)
end

print_tool_result(result) = begin
    print(Crayon(background = (35, 61, 28)))  # Set background
    print("\e[K")  # Clear to end of line with current background color
    print(result, "\e[0m")
end 

function parse_tool(first_line::String, content::String=""; kwargs=Dict())
    tag_end = findfirst(' ', first_line)
    name = String(strip(first_line[1:something(tag_end, length(first_line))]))
    args = isnothing(tag_end) ? "" : String(strip(first_line[tag_end+1:end]))

    # Remove #STOPSEQ from args if present
    if endswith(args, " $STOP_SEQUENCE")    
        args = strip(args[1:end-length(" $STOP_SEQUENCE")])
    end

    # Handle quoted arguments by removing outer quotes if present
    # e.g.: "my query" -> my query
    if !isempty(args)
        args = strip(args)
        # If there's only one quoted argument, remove the quotes
        if length(args) >= 2 && args[1] == '"' && args[end] == '"' && count(c -> c == '"', args) == 2
            args = args[2:end-1]
        end
    end
    
    ToolTag(name=name, args=args, content=content, kwargs=kwargs)
end
