
const click_skill = Skill(
    name="CLICK",
    skill_description="Click on the given coordinates using format: <CLICK x y/>",
    stop_sequence=ONELINER_SS
)

@kwdef struct ClickCommand <: AbstractCommand
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end

ClickCommand(cmd::Command) = ClickCommand(button=:left, x=parse(Int, first(cmd.args)), y=parse(Int, cmd.args[2]))

execute(cmd::ClickCommand) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"

