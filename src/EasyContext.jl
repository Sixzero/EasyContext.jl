module EasyContext

using DataStructures
using BoilerplateCvikli: @async_showerr

using Anthropic
using Anthropic: format_meta_info

using Dates
using UUIDs

using PromptingTools

include("utils.jl")
include("ContextStructs.jl")
include("protocol/CTX.jl")
include("protocol/Message.jl")
include("protocol/CodeBlock.jl")
include("protocol/Conversation.jl")
include("protocol/History.jl")
include("anthropic_extension.jl")
include("Rephrase.v1.jl")
include("chunkers/StandardChunkFormat.jl")
include("RateLimiterRPM.jl")
include("RateLimiterHeader.jl")
include("RateLimiterTPM.jl")
include("chunkers/GolemSourceChunks.jl")
include("chunkers/FullFileChunkerOld.jl")
include("chunkers/FullFileChunker.jl")
include("embedders/EmbedderUtils.jl")
include("ContextJoiner.jl")
include("filters/AgeTracker.jl")
include("file_io/custom_format.jl")
include("rerankers/ReduceRerankGPT.jl")
include("contexts/Contexts.jl")
include("loader/workspace.jl")
include("action/loading_spinner.jl")

# include("ai_repl.jl")
include("PkgLister.jl")
export find_package_path

include("MainUtils.jl")
include("transform/transformations.jl")
# include("AISHExtension.jl")
# include("AISHExtensionV2.jl")
# include("AISHExtensionV3.jl")
# include("AISHExtensionV4.jl")

include("precompile_scripts.jl")

end # module EasyContext


