using HTTP
using JSON3

abstract type AbstractDiffView end
keywords(::Type{<:AbstractDiffView}) = String[]
keywords(view::AbstractDiffView) = keywords(typeof(view))

const DIFFVIEW_SUBTYPES = Vector{Type{<:AbstractDiffView}}()
function register_diffview_subtype!(T::Type{<:AbstractDiffView})
    push!(DIFFVIEW_SUBTYPES, T)
end
        
get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"



