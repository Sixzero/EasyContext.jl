const key_skill = Skill(
    name="SENDKEY",
    description="Send keyboard input using format: <SENDKEY text $(STOP_SEQUENCE)/>",
    stop_sequence=ONELINER_SS
)

@kwdef struct KeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end
has_stop_sequence(cmd::KeyCommand) = true

KeyCommand(cmd::Command) = KeyCommand(text=cmd.args)

execute(cmd::KeyCommand) = "Sending keys: $(cmd.text)"
