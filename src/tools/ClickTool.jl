
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
toolname(::Type{ClickTool}) = "click"
const CLICK_SCHEMA = (
    name = "click",
    description = "Click on screen coordinates",
    params = [
        (name = "x", type = "number", description = "X coordinate", required = true),
        (name = "y", type = "number", description = "Y coordinate", required = true),
    ]
)
get_tool_schema(::Type{ClickTool}) = CLICK_SCHEMA
get_description(::Type{ClickTool}) = description_from_schema(CLICK_SCHEMA)

execute(tool::ClickTool; no_confirm=false) = "Clicking at coordinates ($(tool.x), $(tool.y)) with $(tool.button) button"
tool_format(::Type{ClickTool}) = :single_line
