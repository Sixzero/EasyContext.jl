const key_skill = Skill(
    name="SENDKEY",
    description="Send keyboard input using format: $(SENDKEY_TAG) text $(STOP_SEQUENCE)",
    stop_sequence=STOP_SEQUENCE
)

@kwdef struct SendKeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end
has_stop_sequence(cmd::SendKeyCommand) = true

SendKeyCommand(cmd::Command) = SendKeyCommand(text=cmd.args)

execute(cmd::SendKeyCommand) = "Sending keys: $(cmd.text)"
