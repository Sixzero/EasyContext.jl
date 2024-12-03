

const cat_file_skill = """
when you need the content of a file to solve the task you can use the CATFILE command:
To get the content of a file you can use the CATFILE command:
<$CATFILE_TAG path/to/file $ONELINER_SS>
or if you don't need immediately:
<$CATFILE_TAG path/to/file/>
"""

const catfile_skill = Skill(
    name=CATFILE_TAG,
    description=cat_file_skill,
    stop_sequence=ONELINER_SS,
)

@kwdef struct CatFileCommand <: AbstractCommand
    id::UUID = uuid4()
    file_path::String
    root_path::String
end
CatFileCommand(cmd::Command) = CatFileCommand(file_path=cmd.args[1], root_path=get(cmd.kwargs, "root_path", ""))

execute(cmd::CatFileCommand) = let
    path = normpath(joinpath(cmd.root_path, cmd.file_path))
    isfile(path) ? read(path, String) : "cat: $(path): No such file or directory"
end


