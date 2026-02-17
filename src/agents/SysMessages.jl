
export SysMessageV1, SysMessageV2, SysMessageWithTools

"""
Abstract type for system messages that can create themselves
"""
abstract type AbstractSysMessage end

"""
SysMessageV1 is a system message type that can create itself using a provided function
"""
@kwdef mutable struct SysMessageV1 <: AbstractSysMessage
    sys_msg::String
    content::String = ""
end

"""
SysMessageV2 extends SysMessageV1 with support for custom system messages from AgentSettings
"""
@kwdef mutable struct SysMessageV2 <: AbstractSysMessage
    sys_msg::String
    custom_system_message::Union{String, Nothing} = nothing
    content::String = ""
end

"""
SysMessageWithTools provides a minimal system message with only tools and custom content
"""
@kwdef mutable struct SysMessageWithTools <: AbstractSysMessage
    custom_system_prompt::String = ""
    content::String = ""
end

# Add structural equality (compare configuration fields, ignore content)
import Base: ==

==(a::AbstractSysMessage, b::AbstractSysMessage) = false
==(a::SysMessageV1, b::SysMessageV1) = a.sys_msg == b.sys_msg
==(a::SysMessageV2, b::SysMessageV2) = a.sys_msg == b.sys_msg && a.custom_system_message == b.custom_system_message
==(a::SysMessageWithTools, b::SysMessageWithTools) = a.custom_system_prompt == b.custom_system_prompt

# Build tool section: only extra descriptions (API provides tool schemas natively)
function build_tool_section(tools)
    extra = join(filter(x -> !isnothing(x) && !isempty(x), get_extra_description.(tools)), "\n\n")
    isempty(extra) ? "" : extra
end

# Helper function to build the base system message content (for Default Coder)
function build_base_system_content(sys_msg::String, tools)
    tool_section = build_tool_section(tools)

    """$(sys_msg)

    $(dont_act_chaotic)
    $(simplicity_guide)

    Follow SOLID, KISS and DRY principles.
    Reference files as `path/to/file.ext:line` so they're clickable.
    Keep going until the task is fully resolved before yielding back. Prefer action over asking — only ask when there's genuine ambiguity with multiple valid approaches. After changes, verify they work.

    $(tool_section)

    If a tool doesn't return results, don't rerun it - just note that you didn't receive results from that tool."""
end

# Helper function to build custom system message with tools
function build_custom_with_tools_content(custom_system_prompt::String, tools)
    base_content = isempty(custom_system_prompt) ? "" : "$(custom_system_prompt)\n\n"
    tool_section = build_tool_section(tools)

    """$(base_content)$(tool_section)
    If a tool doesn't return results, don't rerun it - just note that you didn't receive results from that tool."""
end

# Initialize SysMessageV1 using the shared base content
function initialize!(sys::SysMessageV1, agent, force=false)
    if isempty(sys.content) || force
        sys.content = build_base_system_content(sys.sys_msg, agent.tools)
    end
    return sys.content
end

# Initialize SysMessageV2 with custom message support
function initialize!(sys::SysMessageV2, agent, force=false)
    if isempty(sys.content) || force
        base_content = build_base_system_content(sys.sys_msg, agent.tools)
        custom_part = isnothing(sys.custom_system_message) || isempty(sys.custom_system_message) ?
            "" : "\n\n$(sys.custom_system_message)"
        sys.content = base_content * custom_part
    end
    return sys.content
end

# Initialize SysMessageWithTools with custom content and tools
function initialize!(sys::SysMessageWithTools, agent, force=false)
    if isempty(sys.content) || force
        sys.content = build_custom_with_tools_content(sys.custom_system_prompt, agent.tools)
    end
    return sys.content
end
