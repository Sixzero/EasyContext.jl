using PromptingTools.Experimental.RAGTools: AbstractEmbedder

abstract type AbstractEasyEmbedder <: AbstractEmbedder end

get_model_name(embedder::AbstractEasyEmbedder) = embedder.model
