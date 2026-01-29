using ToolCallFormat: ParsedCall

@kwdef struct SendKeyTool <: AbstractTool
    id::UUID = uuid4()
    text::String
end
function create_tool(::Type{SendKeyTool}, call::ParsedCall)
    text = get(call.kwargs, "text", nothing)
    SendKeyTool(text=text !== nothing ? text.value : "")
end

toolname(cmd::Type{SendKeyTool}) = "send_key"
const SENDKEY_SCHEMA = (
    name = "send_key",
    description = "Send keyboard input",
    params = [(name = "text", type = "string", description = "Text to send", required = true)]
)
get_tool_schema(::Type{SendKeyTool}) = SENDKEY_SCHEMA
get_description(cmd::Type{SendKeyTool}) = description_from_schema(SENDKEY_SCHEMA)
tool_format(::Type{SendKeyTool}) = :single_line

execute(cmd::SendKeyTool; no_confirm=false) = "Sending keys: $(cmd.text)"
