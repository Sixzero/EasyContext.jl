

const cat_file_skill_prompt = """
Whenever you need the content of a file to solve the task you can use the CATFILE command:
To get the content of a file you can use the CATFILE command:
$(CATFILE_TAG) path/to/file $(STOP_SEQUENCE)
$(CATFILE_TAG) filepath $(STOP_SEQUENCE)
or if you don't need immediat result from it then you can use it without $STOP_SEQUENCE:
"""

const catfile_skill = Skill(
    name=CATFILE_TAG,
    description=cat_file_skill_prompt,
    stop_sequence=STOP_SEQUENCE,
)

@kwdef struct CatFileCommand <: AbstractCommand
    id::UUID = uuid4()
    file_path::String
    root_path::String
end
has_stop_sequence(cmd::CatFileCommand) = true
CatFileCommand(cmd::Command) = CatFileCommand(id=uuid4(), file_path=cmd.args, root_path=get(cmd.kwargs, "root_path", ""))

execute(cmd::CatFileCommand) = let
    path = normpath(joinpath(cmd.root_path, cmd.file_path))
    # TODO: use STANDARD file print format! So don't redefine this again ang again... Also language detection to the tags would be nice to have
    isfile(path) ? file_format(path, read(path, String)) : "cat: $(path): No such file or directory"
end


