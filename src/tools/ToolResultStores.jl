
abstract type AbstractToolResults end
@kwdef struct StoreInMem <: AbstractToolResults
    tool_results::IdDict{AbstractTool, String} = IdDict()
end
@kwdef struct ServerToolResults <: AbstractToolResults
    tool_results_history::IdDict{AbstractTool, Vector{String}} = IdDict()
end


function set_tool_result(tool_store::StoreInMem, tool::AbstractTool, result::String)
    tool_store.tool_results[tool] = result
end
function get_tool_result(tool_store::StoreInMem, tool::AbstractTool)
    tool_store.tool_results[tool]
end