
@kwdef struct ClickTool <: AbstractTool
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end
function ClickTool(tag::ToolTag)
    args = split(strip(tag.args))
    if length(args) == 3
        ClickTool(button=Symbol(args[1]), x=parse(Int, args[2]), y=parse(Int, args[3]))
    else
        ClickTool(button=:left, x=parse(Int, args[1]), y=parse(Int, args[2]))
    end
end
toolname(::Type{ClickTool}) = CLICK_TAG
get_description(::Type{ClickTool}) = "Click on the given coordinates using format: $(CLICK_TAG) x y $(STOP_SEQUENCE)"
stop_sequence(::Type{ClickTool}) = STOP_SEQUENCE
instantiate(::Val{Symbol(CLICK_TAG)}, tag::ToolTag) = ClickTool(tag)

execute(tool::ClickTool; no_confirm=false) = "Clicking at coordinates ($(tool.x), $(tool.y)) with $(tool.button) button"
tool_format(::Type{ClickTool}) = :single_line
