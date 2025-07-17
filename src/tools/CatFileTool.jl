
@kwdef mutable struct CatFileTool <: AbstractTool
    id::UUID = uuid4()
    file_path::Union{String, AbstractPath}
    root_path::Union{String, AbstractPath, Nothing} = nothing
    result::String = ""
end
create_tool(::Type{CatFileTool}, cmd::ToolTag) = begin
    file_path = cmd.args
    root_path = get(cmd.kwargs, "root_path", nothing)
    CatFileTool(; id=uuid4(), file_path, root_path)
end

toolname(cmd::Type{CatFileTool}) = CATFILE_TAG
get_description(cmd::Type{CatFileTool}) = """
Whenever you need the content of a file to solve the task you can use the CATFILE tool:
To get the content of a file you can use the CATFILE tool:
$(CATFILE_TAG) path/to/file $(STOP_SEQUENCE)
$(CATFILE_TAG) filepath $(STOP_SEQUENCE)
or if you don't need immediat result from it then you can use it without $STOP_SEQUENCE.
"""

stop_sequence(cmd::Type{CatFileTool}) = STOP_SEQUENCE
tool_format(::Type{CatFileTool}) = :single_line

execute(cmd::CatFileTool; no_confirm::Bool=false) = let
    # Use the utility function to handle path expansion
    path = expand_path(cmd.file_path, cmd.root_path)
    cmd.result = isfile(path) ? file_format(path, read(path, String)) : "cat: $(path): No such file or directory"
end

function LLM_safetorun(cmd::CatFileTool) 
    true
end
result2string(tool::CatFileTool)::String = tool.result

execute_required_tools(::CatFileTool) = true