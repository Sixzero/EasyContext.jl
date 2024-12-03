const click_skill = Skill(
    name="CLICK",
    description="Click on the given coordinates using format: <CLICK x y/>",
    stop_sequence=ONELINER_SS
)

@kwdef struct ClickCommand <: AbstractCommand
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end

function ClickCommand(cmd::Command)
    args = split(strip(cmd.args))
    if length(args) == 3
        ClickCommand(button=Symbol(args[1]), x=parse(Int, args[2]), y=parse(Int, args[3]))
    else
        ClickCommand(button=:left, x=parse(Int, args[1]), y=parse(Int, args[2]))
    end
end

execute(cmd::ClickCommand) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"

