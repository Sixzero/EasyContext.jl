const key_skill = Skill(
    name="SENDKEY",
    description="Send keyboard input using format: <SENDKEY text/>",
    stop_sequence=ONELINER_SS
)

@kwdef struct KeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end

KeyCommand(cmd::Command) = KeyCommand(text=cmd.args)

execute(cmd::KeyCommand) = "Sending keys: $(cmd.text)"
