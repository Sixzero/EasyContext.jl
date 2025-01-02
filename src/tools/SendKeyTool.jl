
@kwdef struct SendKeyTool <: AbstractTool
    id::UUID = uuid4()
    text::String
end
SendKeyTool(cmd::ToolTag) = SendKeyTool(text=cmd.args)
instantiate(::Val{Symbol(SENDKEY_TAG)}, cmd::ToolTag) = SendKeyTool(cmd)

commandname(cmd::Type{SendKeyTool}) = SENDKEY_TAG
get_description(cmd::Type{SendKeyTool}) = "Send keyboard input using format: $(SENDKEY_TAG) text $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{SendKeyTool}) = ""

execute(cmd::SendKeyTool) = "Sending keys: $(cmd.text)"
