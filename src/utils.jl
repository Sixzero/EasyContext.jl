
clearline() = print("\033[1\033[G\033[2K")

noop() = nothing
noop(_) = nothing
noop(_,_) = nothing

is_really_empty(user_question) = isempty(strip(user_question))

genid() = string(UUIDs.uuid4()) 



home_abrev(path::AbstractString) = startswith(path, homedir()) ? joinpath("~", relpath(path, homedir())) : path

