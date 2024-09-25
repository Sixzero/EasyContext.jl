module EasyContext

using DataStructures
using BoilerplateCvikli: @async_showerr

using Anthropic
using Anthropic: format_meta_info

using Dates
using UUIDs

include("utils.jl")
include("core/Message.jl")
include("core/CodeBlock.jl")
include("core/Conversation.jl")
include("anthropic_extension.jl")
include("ContextStructs.jl")
include("Rephrase.v1.jl")
include("RateLimiterStruct.jl")
include("chunkers/GolemSourceChunks.jl")
include("chunkers/FullFileChunker.jl")
include("embedders/EmbedderUtils.jl")
include("ContextJoiner.jl")
include("file_io/custom_format.jl")
include("rerankers/ReduceRerankGPT.jl")

# include("ai_repl.jl")
include("PkgLister.jl")
export find_package_path

include("MainUtils.jl")
include("contexts/ContextProcessors.jl")
# include("AISHExtension.jl")
# include("AISHExtensionV2.jl")
# include("AISHExtensionV3.jl")
# include("AISHExtensionV4.jl")

include("precompile_scripts.jl")

end # module EasyContext


