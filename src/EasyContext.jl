module EasyContext

using DataStructures
using BoilerplateCvikli: @async_showerr

using Anthropic
import Anthropic: ai_stream_safe, ai_ask_safe

using Dates
using UUIDs

using PromptingTools

include("utils/utils.jl")
include("action/greet.jl")
include("utils/TokenEstimationMethods.jl")

include("directions/skills.jl")
include("directions/guides.jl")
include("ContextStructs.jl")
include("file_io/custom_format.jl")
include("file_io/Persistable.jl")
include("file_io/GitTracker.jl")
include("protocol/AbstractTypes.jl")
include("protocol/CTX.jl")
include("protocol/Message.jl")
include("protocol/CodeBlock.jl")
include("protocol/Conversation.jl")
include("protocol/History.jl")
include("protocol/Test.jl")
include("anthropic_extension.jl")
include("Rephrase.v1.jl")
include("ratelimiters/init.jl")
include("chunkers/SourceChunks.jl")
include("chunkers/FullFileChunker.jl")
# include("chunkers/FullFileChunker_new.jl")
include("embedders/EmbedderUtils.jl")
include("embedders/EmbeddingContext.jl")
include("ContextJoiner.jl")
include("rerankers/ReduceRerankGPT.jl")
include("rerankers/CohereRerankPro.jl")
include("rerankers/RerankGPTPro.jl")
include("contexts/Contexts.jl")
include("loader/loaders.jl")
include("action/loading_spinner.jl")

include("processor/CodeBlockExtractor.jl")


# include("ai_repl.jl")
include("PkgLister.jl")

include("MainUtils.jl")
include("transform/transformations.jl")



include("building_block/CTX_conversation.jl")
include("building_block/CTX_julia.jl")
include("building_block/CTX_workspace.jl")
include("filter/AgeTracker.jl")

# Automation
include("automation/selector_llm.jl")
include("automation/condition_llm.jl")


include("precompile_scripts.jl")

end # module EasyContext

