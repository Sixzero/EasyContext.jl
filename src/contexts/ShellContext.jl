@kwdef mutable struct ShellContext <: AbstractContextProcessor
    call_counter::Int = 0
end

function get_context(processor::ShellContext, question::String, ai_state, shell_results)
    processor.call_counter += 1
    
    return format_shell_results(shell_results)
end

function AISH.cut_history!(processor::ShellContext, keep::Int)
    # ShellContextProcessor doesn't store any history
    processor.call_counter = 0
end
