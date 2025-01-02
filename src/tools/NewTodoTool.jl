
@kwdef struct NewTodoTool <: AbstractTool
    id::UUID = uuid4()
    title::String
    description::String
end
function NewTodoTool(cmd::ToolTag)
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
commandname(cmd::Type{NewTodoTool}) = NEW_TODO_TAG


execute(cmd::ClickCommand) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"

