# Compatibility layer for legacy EasyContext versions (0.6.0 and earlier)
# This file handles JLD2 serialization/deserialization for older struct formats

using JLD2

# FluidAgent saved with an older field layout: parameterized FluidAgent{SysMessageV2} (0.6.0),
# or before sysmsg_patch/native_tools_patch were added. Copy known fields; the rest use defaults.
const LegacyFluidAgent = Union{
    JLD2.ReconstructedMutable{Symbol("EasyContext.FluidAgent")},
    JLD2.ReconstructedMutable{Symbol("EasyContext.FluidAgent{EasyContext.SysMessageV2}")},
}
saved_fields(::JLD2.ReconstructedMutable{N,FN}) where {N,FN} = FN
Base.convert(::Type{FluidAgent}, x::LegacyFluidAgent) =
    FluidAgent(; (f => getproperty(x, f) for f in saved_fields(x) if f in fieldnames(FluidAgent))...)

# Closures/anonymous functions can't survive JLD2 roundtrips across code changes.
# Tools containing Function fields are rebuilt from agent_settings on restore via
# refresh_agent_from_settings!, so a placeholder is safe here.
function Base.convert(::Type{Function}, x::JLD2.ReconstructedSingleton)
    @warn "JLD2 deserialized a stale closure, substituting identity" type=typeof(x)
    identity
end
function Base.convert(::Type{Union{Function, Nothing}}, x::JLD2.ReconstructedSingleton)
    @warn "JLD2 deserialized a stale closure, substituting nothing" type=typeof(x)
    nothing
end