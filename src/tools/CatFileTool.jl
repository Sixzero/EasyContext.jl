
@kwdef struct CatFileTool <: AbstractTool
    id::UUID = uuid4()
    file_path::String
    root_path::String
end
CatFileTool(cmd::ToolTag) = CatFileTool(id=uuid4(), file_path=cmd.args, root_path=get(cmd.kwargs, "root_path", ""))
instantiate(::Val{Symbol(CATFILE_TAG)}, cmd::ToolTag) = CatFileTool(cmd)

toolname(cmd::Type{CatFileTool}) = CATFILE_TAG
get_description(cmd::Type{CatFileTool}) = """
Whenever you need the content of a file to solve the task you can use the CATFILE tool:
To get the content of a file you can use the CATFILE tool:
$(CATFILE_TAG) path/to/file $(STOP_SEQUENCE)
$(CATFILE_TAG) filepath $(STOP_SEQUENCE)
or if you don't need immediat result from it then you can use it without $STOP_SEQUENCE:
"""
stop_sequence(cmd::Type{CatFileTool}) = STOP_SEQUENCE

execute(cmd::CatFileTool, no_confirm::Bool=false) = let
    path = normpath(joinpath(cmd.root_path, cmd.file_path))
    # TODO: use STANDARD file print format! So don't redefine this again ang again... Also language detection to the tags would be nice to have
    isfile(path) ? file_format(path, read(path, String)) : "cat: $(path): No such file or directory"
end

function LLM_safetorun(cmd::CatFileTool) 
    true
end