module EasyContext


greet() = print("Hello World!")
export JuliacodeRephraser

include("GolemSourceChunks.jl")
include("Rephrase.v1.jl")
include("CacheBatchEmbedder.jl")
include("ContextJoiner.jl")
include("RerankReduce.jl")
include("FullFileChunker.jl")

include("PkgLister.jl")
export find_package_path

include("Main.jl")
include("AISHExtension.jl")

end # module EasyContext
