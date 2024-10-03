using PromptingTools.Experimental.RAGTools: AbstractEmbedder

abstract type Cacheable end
abstract type AbstractLoader <: Cacheable end

abstract type AbstractContextCreator end

abstract type CombinationMethod end

abstract type AbstractIndexBuilder <: Cacheable end
abstract type AbstractEasyEmbedder <: AbstractEmbedder end


abstract type BLOCK end
abstract type CONV end
abstract type MSG end

