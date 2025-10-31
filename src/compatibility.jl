# Compatibility layer for legacy EasyContext versions (0.6.0 and earlier)
# This file handles JLD2 serialization/deserialization for older struct formats

using JLD2

# FluidAgent compatibility for parameterized types from 0.6.0
function Base.convert(::Type{FluidAgent}, x::JLD2.ReconstructedMutable{Symbol("EasyContext.FluidAgent{EasyContext.SysMessageV2}")})
    FluidAgent(
        tools = x.tools,
        model = x.model,
        workspace = x.workspace,
        extractor_type = x.extractor_type,
        sys_msg = x.sys_msg
    )
end

# Add more legacy compatibility converters here as they come up
# Example pattern:
# function Base.convert(::Type{ModernType}, x::JLD2.ReconstructedMutable{Symbol("EasyContext.LegacyType")})
#     ModernType(field1 = x.field1, field2 = get(x, :field2, default_value))
# end