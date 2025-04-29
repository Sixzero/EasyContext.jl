
@kwdef mutable struct CatFileTool <: AbstractTool
    id::UUID = uuid4()
    file_path::Union{String, AbstractPath}
    result::String = ""
end
create_tool(::Type{CatFileTool}, cmd::ToolTag, root_path=nothing) = begin
    file_path = expand_path(cmd.args, root_path === nothing ? get(cmd.kwargs, "root_path", "") : root_path)
    CatFileTool(; id=uuid4(), file_path)
end

instantiate(::Val{Symbol(CATFILE_TAG)}, cmd::ToolTag) = CatFileTool(cmd)

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
    cmd.result = isfile(cmd.file_path) ? file_format(cmd.file_path, read(cmd.file_path, String)) : "cat: $(cmd.file_path): No such file or directory"
end

function LLM_safetorun(cmd::CatFileTool) 
    true
end
result2string(tool::CatFileTool)::String = tool.result

execute_required_tools(::CatFileTool) = true