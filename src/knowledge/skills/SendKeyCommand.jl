
@kwdef struct SendKeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end
SendKeyCommand(cmd::CommandTag) = SendKeyCommand(text=cmd.args)
instantiate(::Val{Symbol(SENDKEY_TAG)}, cmd::CommandTag) = SendKeyCommand(cmd)

commandname(cmd::Type{SendKeyCommand}) = SENDKEY_TAG
get_description(cmd::Type{SendKeyCommand}) = "Send keyboard input using format: $(SENDKEY_TAG) text $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{SendKeyCommand}) = ""


execute(cmd::SendKeyCommand) = "Sending keys: $(cmd.text)"
