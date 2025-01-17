module EasyContext

using DataStructures
using BoilerplateCvikli: @async_showerr
using LLMRateLimiters: TokenEstimationMethod, airatelimited, RateLimiterRPM, RateLimiterTPM, CharCountDivTwo, estimate_tokens

using Dates
using UUIDs

using PromptingTools
using PromptingTools: UserMessage, AIMessage, SystemMessage

include("utils/utils.jl")
include("action/greet.jl")

include("input/input.jl")

include("protocol/Context.jl")
include("tools/formats/format.jl")
include("tools/tools.jl")
include("agents/FluidAgent.jl")
include("prompts/guides.jl")
include("ContextStructs.jl")
include("protocol/AbstractTypes.jl")
include("protocol/Message.jl")
# include("protocol/CodeBlock.jl")
include("protocol/Conversation.jl")
include("protocol/Session.jl")
include("anthropic_extension.jl")
include("Rephrase.v1.jl")
include("chunkers/SourceChunks.jl")
include("chunkers/FullFileChunker.jl")
# include("chunkers/FullFileChunker_new.jl")
include("embedders/EmbedderUtils.jl")
include("embedders/EmbeddingContext.jl")
include("ContextJoiner.jl")
include("rerankers/ChunkBatchers.jl")
include("rerankers/rerank_prompts.jl")
include("rerankers/CohereRerankerPro.jl")
include("rerankers/ReduceGPTReranker.jl")
include("loader/loaders.jl")
include("action/loading_spinner.jl")
# include("action/GroqSpeech.jl")

# include("ai_repl.jl")
include("PkgLister.jl")

include("MainUtils.jl")
include("stateful_transformation/StatefulTransformators.jl")
include("transform/transformations.jl")
include("transform/QueryTransformers.jl")


include("contexts/Contexts.jl")




include("precompile_scripts.jl")

end # module EasyContext

