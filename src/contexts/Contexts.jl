using PromptingTools.Experimental.RAGTools

include("CTX_question.jl")
include("CTX_conversation.jl")
include("CTX_julia.jl")
include("CTX_workspace.jl")

function get_cache_setting(::AbstractContextCreator, conv)
    printstyled("WARNING: get_cache_setting not implemented for this contexter type. Defaulting to no caching.\n", color=:red)
    return nothing
end

get_chunk_standard_format(source, content) = "# $source\n$content"
get_chunk_standard_format(d::T) where {T<:AbstractDict} = T(src => get_chunk_standard_format(src, content) for (src, content) in d)

function default_source_parser(source::String, current_content::String)
    updated_content = get_updated_content(source)
    return get_chunk_standard_format(source, updated_content)
end