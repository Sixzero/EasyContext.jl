@kwdef mutable struct JuliaPackageContext <: AbstractContextProcessor
    tracked_sources::Dict{String, Tuple{Int, String}} = Dict{String, Tuple{Int, String}}()
    call_counter::Int = 0
end

function get_context(processor::JuliaPackageContext, question::String, ai_state, shell_results)
    processor.call_counter += 1
    result = get_context(question; suppress_output=true)
    new_sources = String[]
    unchanged_sources = String[]
    context = String[]
    
    for (i, source) in enumerate(result.sources)
        if !haskey(processor.tracked_sources, source)
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            processor.tracked_sources[source] = (processor.call_counter, result.context[i])
        elseif processor.tracked_sources[source][2] != result.context[i]
            push!(new_sources, source)
            push!(context, "$(i). $(result.context[i])")
            processor.tracked_sources[source] = (processor.call_counter, result.context[i])
        else
            push!(unchanged_sources, source)
        end
    end
    
    print_context_updates(new_sources, String[], unchanged_sources; item_type="context sources")
    
    context_msg = isempty(context) ? "" : """
    Existing functions in other libraries:
    $(join(context, "\n"))
    """
    return context_msg
end

function AISH.cut_history!(processor::JuliaPackageContext, keep::Int)
    oldest_kept_message = max(1, processor.call_counter - 2 * keep + 1)
    for (source, (msg_num, _)) in processor.tracked_sources
        if msg_num < oldest_kept_message
            delete!(processor.tracked_sources, source)
        end
    end
end
