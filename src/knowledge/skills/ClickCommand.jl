
@kwdef struct ClickCommand <: AbstractCommand
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end
has_stop_sequence(cmd::ClickCommand) = true
get_description(cmd::ClickCommand) = "Click on the given coordinates using format: $(CLICK_TAG) x y $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{<:ClickCommand}) = STOP_SEQUENCE
commandname(cmd::Type{<:ClickCommand}) = CLICK_TAG

function ClickCommand(cmd::CommandTag)
    args = split(strip(cmd.args))
    if length(args) == 3
        ClickCommand(button=Symbol(args[1]), x=parse(Int, args[2]), y=parse(Int, args[3]))
    else
        ClickCommand(button=:left, x=parse(Int, args[1]), y=parse(Int, args[2]))
    end
end

execute(cmd::ClickCommand) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"

