
@kwdef struct ClickTool <: AbstractTool
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end
function ClickTool(cmd::ToolTag)
    args = split(strip(cmd.args))
    if length(args) == 3
        ClickTool(button=Symbol(args[1]), x=parse(Int, args[2]), y=parse(Int, args[3]))
    else
        ClickTool(button=:left, x=parse(Int, args[1]), y=parse(Int, args[2]))
    end
end
commandname(cmd::Type{ClickTool}) = CLICK_TAG
get_description(cmd::Type{ClickTool}) = "Click on the given coordinates using format: $(CLICK_TAG) x y $(STOP_SEQUENCE)"
stop_sequence(cmd::Type{ClickTool}) = STOP_SEQUENCE
instantiate(::Val{Symbol(CLICK_TAG)}, cmd::ToolTag) = ClickTool(cmd)

execute(cmd::ClickTool) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"