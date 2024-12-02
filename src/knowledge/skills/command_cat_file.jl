const CATFILE_TAG = "CATFILE"

const cat_file_skill = """
when you need the content of a file to solve the task you can use the CATFILE command:
To get the content of a file you can use the CATFILE command:
<$CATFILE_TAG path/to/file $ONELINER_SS>
or if you don't need immediately:
<$CATFILE_TAG path/to/file/>
"""

const catfile_skill = Skill(
    name=CATFILE_TAG,
    skill_description=cat_file_skill,
    stop_sequence=ONELINER_SS,
)

@kwdef struct CatFileCommand <: AbstractCommand
    id::UUID = uuid4()
    path::String
    content::String = ""
end

function CatFileCommand(cmd::Command)
    CatFileCommand(
        path=first(cmd.args),
        content=""
    )
end

execute(cmd::CatFileCommand) = isfile(cmd.path) ? read(cmd.path, String) : "cat: $(cmd.path): No such file or directory"


