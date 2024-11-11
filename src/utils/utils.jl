using ULID: encoderandom, encodetime


noop() = nothing
noop(_) = nothing
noop(_,_) = nothing

is_really_empty(user_question) = isempty(strip(user_question))

genid() = string(UUIDs.uuid4()) 

short_ulid() = encodetime(floor(Int,datetime2unix(now())*1000),10)*encoderandom(8)

home_abrev(path::AbstractString) = startswith(path, homedir()) ? joinpath("~", relpath(path, homedir())) : path


mkpath_if_missing(path::AbstractString) = isdir(expanduser(path)) || mkdir(expanduser(path))



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

# #%%
# import Pkg
# installed_pkgs = @edit Pkg.dependencies()
# #%%
# global_env_path = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)", "Project.toml")
# @time ctx = @edit Pkg.Types.EnvCache((global_env_path))
# ;
# ;
# #%%
# using Pkg.Types: manifestfile_path, write_env_usage, read_manifest
# project = Pkg.Types.read_project(global_env_path)

# dir = abspath(global_env_path)
# manifest_file = project.manifest
# manifest_file = manifest_file !== nothing ?
# 		(isabspath(manifest_file) ? manifest_file : abspath(dir, manifest_file)) :
# 		manifestfile_path(dir)::String
# write_env_usage(manifest_file, "manifest_usage.toml")
# @time manifest = read_manifest(manifest_file)

# #%%
# @time global_env = Pkg.Types.EnvCache(global_env_path)
# @time all_dependencies = Pkg.dependencies(global_env)
# #%%
# using Pkg.Operations
# function ssource_path(manifest_file::String, pkg, julia_version = VERSION)
#     pkg.tree_hash   !== nothing ? find_installed(pkg.name, pkg.uuid, pkg.tree_hash) :
#     pkg.path        !== nothing ? joinpath(dirname(manifest_file), pkg.path) :
#     is_or_was_stdlib(pkg.uuid, julia_version) ? Types.stdlib_path(pkg.name) :
#     nothing
# end
# Operations.project_rel_path(env, ssource_path(env.manifest_file, pkg))
# #%%
# import Pkg
# global_env_path = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)", "Project.toml")
# project = Pkg.Types.read_project(global_env_path)
# deps = Dict()

# for (name, uuid) in project.deps
# 		version = get(project.compat, name, nothing)
# 		pkg_info = Pkg.Types.PackageSpec(; name=name, uuid=uuid)
# 		@show pkg_info
# 		source = @edit Pkg.Operations.source_path(active_project, pkg_info)
# 		@show source
# end