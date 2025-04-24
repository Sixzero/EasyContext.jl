
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
get_description(cmd::Type{NewTodoTool}) = """
Create a new todo with title and description using format: 
$(NEW_TODO_TAG) project_name message
"""
stop_sequence(cmd::Type{NewTodoTool}) = ""
toolname(cmd::Type{NewTodoTool}) = NEW_TODO_TAG

execute(cmd::NewTodoTool) = "Creating todo: $(cmd.title) - $(cmd.description)"

