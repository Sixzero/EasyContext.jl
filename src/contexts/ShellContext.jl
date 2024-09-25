@kwdef mutable struct ShellContext <: AbstractContextProcessor
    call_counter::Int = 0
end

function (processor::ShellContext)(result, shell_results=nothing)
    processor.call_counter += 1
    
    if isnothing(shell_results)
        @assert false "No shell results from last message."
    end
    
    formatted_results = format_shell_results_to_context(shell_results)
    
    return formatted_results
end
function get_context(processor::ShellContext, question::String, shell_results)
    processor.call_counter += 1
    
    return format_shell_results_to_context(shell_results)
end

function cut_history!(processor::ShellContext, keep::Int)
    # ShellContextProcessor doesn't store any history
    processor.call_counter = 0
end
