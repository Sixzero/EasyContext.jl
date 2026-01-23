
@kwdef struct ClickTool <: AbstractTool
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end
function create_tool(::Type{ClickTool}, tag::ToolTag)
    args = split(strip(tag.args))
    if length(args) == 3
        ClickTool(button=Symbol(args[1]), x=parse(Int, args[2]), y=parse(Int, args[3]))
    else
        ClickTool(button=:left, x=parse(Int, args[1]), y=parse(Int, args[2]))
    end
end
toolname(::Type{ClickTool}) = CLICK_TAG
get_description(::Type{ClickTool}) = """
Click on coordinates:
$(CLICK_TAG) x y
"""
stop_sequence(::Type{ClickTool}) = STOP_SEQUENCE

execute(tool::ClickTool; no_confirm=false) = "Clicking at coordinates ($(tool.x), $(tool.y)) with $(tool.button) button"
tool_format(::Type{ClickTool}) = :single_line
