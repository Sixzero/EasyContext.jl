
@kwdef struct SendKeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end
commandname(cmd::Type{<:SendKeyCommand}) = SENDKEY_TAG
get_description(cmd::SendKeyCommand) = "Send keyboard input using format: $(SENDKEY_TAG) text $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{<:SendKeyCommand}) = ""
has_stop_sequence(cmd::SendKeyCommand) = true

SendKeyCommand(cmd::CommandTag) = SendKeyCommand(text=cmd.args)

execute(cmd::SendKeyCommand) = "Sending keys: $(cmd.text)"
