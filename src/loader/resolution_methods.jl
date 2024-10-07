abstract type AbstractResolutionMethod end

struct FirstAsRootResolution <: AbstractResolutionMethod end
struct LongestCommonPathResolution <: AbstractResolutionMethod end


function resolve(::FirstAsRootResolution, paths::Vector{String})
    isempty(paths) && return "", String[]
    root_path = abspath(paths[1])
    relative_paths = ["."]
    for path in paths[2:end]
        abs_path = abspath(path)
        rel_path = relpath(abs_path, root_path)
        push!(relative_paths, rel_path)
    end
    return root_path, relative_paths
end

function resolve(::LongestCommonPathResolution, paths::Vector{String})
    isempty(paths) && return "", String[]
    length(paths) == 1 && return abspath(paths[1]), ["."]
    
    abs_paths = abspath.(paths)
    common_path = longestcommonpath(abs_paths)
    
    relative_paths = relpath.(abs_paths, common_path)
    
    return common_path, relative_paths
end

function longestcommonpath(paths)
    isempty(paths) && return ""
    splitted_paths = splitpath.(paths)
    for i in 1:length(first(splitted_paths))
        if !all(p -> length(p) >= i && p[i] == first(splitted_paths)[i], splitted_paths)
            return joinpath(first(splitted_paths)[1:i-1])
        end
    end
    return first(paths)
end
