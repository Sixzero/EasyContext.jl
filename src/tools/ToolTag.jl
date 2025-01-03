export print_tool_result

include("ToolInterface.jl")


@kwdef mutable struct ToolTag <: AbstractTag
    name::String
    content::String = ""
    args::String = ""
    kwargs::Dict{String,String} = Dict{String,String}()
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

# CLICK x y
# CLICK x y #RUN
# SENDKEY asdf #RUN
# READFILE path/to/file #RUN
# MODIFY path/to/file
# '''programming language
# content
# '''
# ENDOFFILE
# 
# CREATE path="path/to/space in filename"
# '''language
# content
# '''
# ENDOFFILE
# CREATE path/to/file
# '''language
# content
# '''
# ENDOFFILE
#
# SHELL_RUN command #RUN/>
# SHELL_BLOCK
# '''sh
# content
# '''
# ENDOFFILE
#
# CLICK x y LEFT
# CLICK x y RIGHT
# CLICK x y MIDDLE
