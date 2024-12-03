abstract type AbstractCommand end

@kwdef mutable struct Command <: AbstractCommand
    name::String
    content::String = ""
    args::String = ""
end

function parse_arguments(parts::Vector{SubString{String}})
    args = String[]
    kwargs = Dict{String,String}()
    
    for part in String.(parts)
        # Skip stop sequence
        endswith(part, "#RUN/>") && continue
        endswith(part, "#RUN>") && continue
        
        if contains(part, "=")
            key, value = split(part, "=")
            kwargs[key] = replace(value, "\""=>"")
        else
            push!(args, part)
        end
    end
    args, kwargs
end

# Convert raw Command to specific command types
function convert_command(cmd::Command)
    if cmd.name == "MODIFY"
        return ModifyFileCommand(cmd)
    elseif cmd.name == "SHELL_RUN"
        return ShellCommand(cmd)
    elseif cmd.name == "CREATE"
        return CreateFileCommand(cmd)
    elseif cmd.name == "CLICK"
        return ClickCommand(cmd)
    elseif cmd.name == "KEY"
        return KeyCommand(cmd)
    elseif cmd.name == "READFILE"
        return CatFileCommand(cmd)
    elseif cmd.name == "EMAIL"
        return EmailCommand(cmd)
    else
        error("Unknown command type: $(cmd.name)")
    end
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
