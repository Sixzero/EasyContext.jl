module EasyContext

greet() = print("Hello World!")
export JuliacodeRephraser

include("GolemSourceChunks.jl")
include("Rephrase.v1.jl")
include("CacheBatchEmbedder.jl")
include("ContextJoiner.jl")
include("ReduceRerankGPT.jl")
include("FullFileChunker.jl")

include("PkgLister.jl")
export find_package_path

include("MainUtils.jl")
include("Main.jl")
include("AISHExtension.jl")
include("AISHExtensionV2.jl")
include("AISHExtensionV3.jl")

end # module EasyContext

