export print_tool_result

abstract type AbstractCommand end

has_stop_sequence(cmd::AbstractCommand) = (@warn("UNIMPLEMENTED has_stop_sequence for: $(typeof(cmd))"); false)
@kwdef mutable struct Command <: AbstractCommand
    name::String
    content::String = ""
    args::String = ""
    kwargs::Dict{String,String} = Dict{String,String}()
end



# Convert raw Command to specific command types
function convert_command(cmd::Command)
    if cmd.name == MODIFY_FILE_TAG
        return ModifyFileCommand(cmd)
    elseif cmd.name == SHELL_RUN_TAG
        return ShellCommand(cmd)
    elseif cmd.name == CREATE_FILE_TAG
        return CreateFileCommand(cmd)
    elseif cmd.name == CLICK_TAG
        return ClickCommand(cmd)
    elseif cmd.name == SENDKEY_TAG
        return KeyCommand(cmd)
    elseif cmd.name == CATFILE_TAG
        return CatFileCommand(cmd)
    elseif cmd.name == EMAIL_TAG
        return EmailCommand(cmd)
    elseif cmd.name == WEB_SEARCH_TAG
        return WebSearchCommand(cmd)
    else
        error("Unknown command type: $(cmd.name)")
    end
end

preprocess(cmd::T) where T <: AbstractCommand = cmd

print_tool_result(result) = begin
    print(Crayon(background = (35, 61, 28)))  # Set background
    print("\e[K")  # Clear to end of line with current background color
    print(result, "\e[0m")
end 

# <CLICK x y/>
# <CLICK x y #RUN/>
# <KEY asdf #RUN/>
# <READFILE path/to/file #RUN/>
# <MODIFY path/to/file>
# '''programming language
# content
# '''
# </MODIFY #RUN>
# <CREATE path="path/to/space in filename">
# '''language
# content
# '''
# </CREATE #RUN>
# <CREATE path/to/space in filename>
# '''language
# content
# '''
# </CREATE #RUN>
# <SHELL_RUN command #RUN/>

# <CLICK x y runresult=Success>
