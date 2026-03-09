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