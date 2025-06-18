
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

# Initialize the system message content
function initialize!(sys::SysMessageV1, agent, force=false)
    if isempty(sys.content) || force
        sys.content = """$(sys.sys_msg)

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

        $(get_tool_descriptions(agent.tools))
        
        $(join(filter(x -> !isnothing(x) && !isempty(x), get_extra_description.(agent.tools)), "\n\n"))

        If a tool doesn't return results after asking for results with $STOP_SEQUENCE then don't rerun it, but write, we didn't receive results from the specific tool.

        Follow SOLID, KISS and DRY principles. Be concise!

        $(conversaton_starts_here)"""
    end
    return sys.content
end
