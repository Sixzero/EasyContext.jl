
export SysMessageV1

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

# Helper function to build the base system message content
function build_base_system_content(sys_msg::String, tools)
    """$(sys_msg)

    $(highlight_code_guide)
    $(highlight_changes_guide_v2)
    $(organize_file_guide)

    $(dont_act_chaotic)
    $(refactor_all)
    $(simplicity_guide)
    
    $(ambiguity_guide)
    
    $(test_it_v2)
    
    $(no_loggers)
    $(julia_specific_guide)
    $(system_information)

    $(get_tool_descriptions(tools))
    
    $(join(filter(x -> !isnothing(x) && !isempty(x), get_extra_description.(tools)), "\n\n"))

    If a tool doesn't return results after asking for results with $STOP_SEQUENCE then don't rerun it, but write, we didn't receive results from the specific tool.

    Follow SOLID, KISS and DRY principles. Be concise!

    $(conversaton_starts_here)"""
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
