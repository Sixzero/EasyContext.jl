using ToolCallFormat: ParsedCall

@kwdef struct ClickTool <: AbstractTool
    id::UUID = uuid4()
    button::Symbol
    x::Int
    y::Int
end
function create_tool(::Type{ClickTool}, call::ParsedCall)
    x_pv = get(call.kwargs, "x", nothing)
    y_pv = get(call.kwargs, "y", nothing)
    button_pv = get(call.kwargs, "button", nothing)
    ClickTool(
        button=button_pv !== nothing ? Symbol(button_pv.value) : :left,
        x=x_pv !== nothing ? Int(x_pv.value) : 0,
        y=y_pv !== nothing ? Int(y_pv.value) : 0
    )
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
