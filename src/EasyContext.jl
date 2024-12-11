module EasyContext

using DataStructures
using BoilerplateCvikli: @async_showerr

using Anthropic
import Anthropic: ai_stream_safe, ai_ask_safe

using Dates
using UUIDs

using PromptingTools
using PromptingTools: UserMessage, AIMessage, SystemMessage

include("utils/utils.jl")
include("action/greet.jl")
include("utils/TokenEstimationMethods.jl")

include("protocol/CTX.jl")
include("knowledge/formats/format.jl")
include("knowledge/skills/skills.jl")
include("knowledge/guides/guides.jl")
include("ContextStructs.jl")
include("file_io/custom_format.jl")
include("file_io/Persistable.jl")
include("protocol/AbstractTypes.jl")
include("protocol/Message.jl")
include("protocol/CodeBlock.jl")
include("protocol/Conversation.jl")
include("protocol/Session.jl")
include("protocol/History.jl")
include("protocol/Test.jl")
include("file_io/Conversation_JSON.jl")
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
include("loader/loaders.jl")
include("action/loading_spinner.jl")
# include("action/GroqSpeech.jl")

# include("ai_repl.jl")
include("PkgLister.jl")

include("MainUtils.jl")
include("stateful_transformation/StatefulTransformators.jl")
include("transform/transformations.jl")


include("contexts/Contexts.jl")




# Automation
include("automation/selector_llm.jl")
include("automation/condition_llm.jl")

include("model/persistence.jl")

include("precompile_scripts.jl")

end # module EasyContext

