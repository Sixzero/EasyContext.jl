
@kwdef struct NewTodoTool <: AbstractTool
    id::UUID = uuid4()
    title::String
    description::String
end
function create_tool(::Type{NewTodoTool}, cmd::ToolTag)
    args = split(strip(cmd.args))
    if length(args) == 3
        NewTodoTool(title=args[1], description=args[2])
    else
        NewTodoTool(title=args[1], description=args[2])
    end
end
toolname(cmd::Type{NewTodoTool}) = "new_todo"
stop_sequence(cmd::Type{NewTodoTool}) = ""
const NEWTODO_SCHEMA = (
    name = "new_todo",
    description = "Create a new todo item",
    params = [
        (name = "title", type = "string", description = "Todo title", required = true),
        (name = "description", type = "string", description = "Todo description", required = true),
    ]
)
get_tool_schema(::Type{NewTodoTool}) = NEWTODO_SCHEMA
get_description(cmd::Type{NewTodoTool}) = description_from_schema(NEWTODO_SCHEMA)

execute(cmd::NewTodoTool) = "Creating todo: $(cmd.title) - $(cmd.description)"

