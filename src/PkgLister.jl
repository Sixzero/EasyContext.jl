using Pkg
using Base: relpath


function find_package_path(package_name::String)
  pkg = findfirst(p -> p.name == package_name, Pkg.dependencies())
  if isnothing(pkg)
      @warn "Package $package_name not found"
      return nothing
  end
  
  pkg_info::Pkg.API.PackageInfo = Pkg.dependencies()[pkg]
  full_path = pkg_info.source
  home_dir = homedir()
  if startswith(full_path, home_dir)
    return replace(full_path, home_dir => "~")
  else
    return full_path
  end
end