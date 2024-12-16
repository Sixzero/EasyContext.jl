
@kwdef struct NewTodoCommand <: AbstractCommand
    id::UUID = uuid4()
    title::String
    description::String
end
function NewTodoCommand(cmd::CommandTag)
    args = split(strip(cmd.args))
    if length(args) == 3
        NewTodoCommand(title=args[1], description=args[2])
    else
        NewTodoCommand(title=args[1], description=args[2])
    end
end
get_description(cmd::Type{NewTodoCommand}) = """
Create a new todo with title and description using format: 
$(NEW_TODO_TAG) project_name message
"""
stop_sequence(cmd::Type{NewTodoCommand}) = ""
commandname(cmd::Type{NewTodoCommand}) = NEW_TODO_TAG


execute(cmd::ClickCommand) = "Clicking at coordinates ($(cmd.x), $(cmd.y)) with $(cmd.button) button"

