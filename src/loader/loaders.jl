
abstract type AbstractLoader end

include("token_counter.jl")
include("workspace_file_filters.jl")
include("workspace.jl")

include("julia_loader.jl")
include("python_loader.jl")
