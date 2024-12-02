

const key_skill = Skill(
    name="KEY",
    skill_description="Send keyboard input using format: <KEY text/>",
    stop_sequence=ONELINER_SS
)

@kwdef struct KeyCommand <: AbstractCommand
    id::UUID = uuid4()
    text::String
end

function KeyCommand(cmd::Command)
    KeyCommand(
        text=first(cmd.args)
    )
end

execute(cmd::KeyCommand) = "Sending keys: $(cmd.text)"
