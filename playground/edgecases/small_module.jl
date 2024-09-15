# This file is a part of Julia. License is MIT: https://julialang.org/license

module API

using UUIDs
using Printf
import Random
using Dates

Base.@kwdef struct PackageInfo
    name::String
    version::Union{Nothing,VersionNumber}
    tree_hash::Union{Nothing,String}
    is_direct_dep::Bool
    is_pinned::Bool
    is_tracking_path::Bool
    is_tracking_repo::Bool
    is_tracking_registry::Bool
    git_revision::Union{Nothing,String}
    git_source::Union{Nothing,String}
    source::String
    dependencies::Dict{String,UUID}
end

function upgrade_manifest(man_path::String)
    dir = mktempdir()
    cp(man_path, joinpath(dir, "Manifest.toml"))
    Pkg.activate(dir) do
        Pkg.upgrade_manifest()
    end
    mv(joinpath(dir, "Manifest.toml"), man_path, force = true)
end
function upgrade_manifest(ctx::Context = Context())
    before_format = ctx.env.manifest.manifest_format
    if before_format == v"2.0"
        pkgerror("Format of manifest file at `$(ctx.env.manifest_file)` already up to date: manifest_format == $(before_format)")
    elseif before_format != v"1.0"
        pkgerror("Format of manifest file at `$(ctx.env.manifest_file)` version is unrecognized: manifest_format == $(before_format)")
    end
    ctx.env.manifest.manifest_format = v"2.0"
    Types.write_manifest(ctx.env)
    printpkgstyle(ctx.io, :Updated, "Format of manifest file at `$(ctx.env.manifest_file)` updated from v$(before_format.major).$(before_format.minor) to v2.0")
    return nothing
end

end # module
