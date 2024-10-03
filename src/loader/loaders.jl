
abstract type Cacheable end
abstract type AbstractLoader <: Cacheable end
abstract type AbstractIndexBuilder <: Cacheable end

include("token_counter.jl")
include("workspace_file_filters.jl")
include("workspace.jl")

include("cached_loader.jl")
include("julia_loader.jl")
include("python_loader.jl")
