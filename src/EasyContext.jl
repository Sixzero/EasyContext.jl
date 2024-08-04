module EasyContext


greet() = print("Hello World!")
export JuliacodeRephraser

include("GolemSourceChunks.jl")
include("Rephrase.v1.jl")
include("CacheBatchEmbedder.jl")

include("PkgLister.jl")
export find_package_path

end # module EasyContext
