# Simple trait system for transform position
abstract type TransformPosition end
struct PrependTransform <: TransformPosition end
struct AppendTransform <: TransformPosition end

transform_position(::Type{<:Any}) = AppendTransform()

# Base transform interface
function transform end

# Image transform
@kwdef struct ImageTransform
    enabled::Bool = true
end
transform_position(::Type{ImageTransform}) = PrependTransform()
function transform(t::ImageTransform, query)
    !t.enabled && return nothing
    process_image_in_message(query)
end

# Youtube transform example
# @kwdef struct YoutubeTransform
#     enabled::Bool = true
#     api_key::String
# end
# transform_position(::Type{YoutubeTransform}) = AppendTransform()
# function transform(t::YoutubeTransform, query)
#     !t.enabled && return nothing
#     "<YOUTUBE>transcription</YOUTUBE>"
# end

export transform, transform_position, ImageTransform
