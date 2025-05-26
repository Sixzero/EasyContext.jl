
@kwdef struct SendKeyTool <: AbstractTool
    id::UUID = uuid4()
    text::String
end
create_tool(SendKeyTool, cmd::ToolTag) = SendKeyTool(text=cmd.args)

toolname(cmd::Type{SendKeyTool}) = SENDKEY_TAG
get_description(cmd::Type{SendKeyTool}) = "Send keyboard input using format: $(SENDKEY_TAG) text $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{SendKeyTool}) = ""
tool_format(::Type{SendKeyTool}) = :single_line

execute(cmd::SendKeyTool; no_confirm=false) = "Sending keys: $(cmd.text)"
