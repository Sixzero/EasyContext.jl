using ULID: encoderandom, encodetime

clearline() = print("\033[1\033[G\033[2K")

noop() = nothing
noop(_) = nothing
noop(_,_) = nothing

is_really_empty(user_question) = isempty(strip(user_question))

genid() = string(UUIDs.uuid4()) 

short_ulid() = encodetime(floor(Int,datetime2unix(now())*1000),10)*encoderandom(8)

home_abrev(path::AbstractString) = startswith(path, homedir()) ? joinpath("~", relpath(path, homedir())) : path






import Pkg.Types: Project, read_project, VersionSpec

struct SimplePackageInfo
    uuid::UUID
    name::String
    version::Union{VersionSpec, Nothing}
end

function simplified_dependencies(project_file::String)
	project = read_project(project_file)
	return Dict{UUID, SimplePackageInfo}(
			uuid => SimplePackageInfo(uuid, name, get(project.compat, name, nothing))
			for (name, uuid) in project.deps
	)
end