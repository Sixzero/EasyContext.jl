
"""
    AbstractToolResults

Abstract type for different tool result storage implementations. This allows storing tool 
execution results in different backends like in-memory, SQLite, JLD2 files, etc.

Each concrete implementation needs to define:
- `set_tool_result(store, tool, result)`: Store a result for a tool
- `get_tool_result(store, tool)`: Retrieve the latest result for a tool
"""
abstract type AbstractToolResults end

"""
    StoreInMem

Simple in-memory storage for tool results using an IdDict.

# Fields
- `tool_results::IdDict{AbstractTool, String}`: Maps tools to their latest result
"""
@kwdef struct StoreInMem <: AbstractToolResults
    tool_results::IdDict{AbstractTool, String} = IdDict()
end

"""
    ServerToolResults

Store that keeps history of tool results, useful for server implementations
or persistent storage scenarios.

# Fields
- `tool_results_history::IdDict{AbstractTool, Vector{String}}`: Maps tools to their execution history
"""
@kwdef struct ServerToolResults <: AbstractToolResults
    tool_results_history::IdDict{AbstractTool, Vector{String}} = IdDict()
end

"""
    set_tool_result(tool_store::StoreInMem, tool::AbstractTool, result::String)

Store the latest result for a tool in memory.
"""
function set_tool_result(tool_store::StoreInMem, tool::AbstractTool, result::String)
    tool_store.tool_results[tool] = result
end

"""
    get_tool_result(tool_store::StoreInMem, tool::AbstractTool)

Get the latest result for a tool from memory.
"""
function get_tool_result(tool_store::StoreInMem, tool::AbstractTool)
    tool_store.tool_results[tool]
end

"""
    set_tool_result(tool_store::ServerToolResults, tool::AbstractTool, result::String)

Store tool result while maintaining execution history.
"""
function set_tool_result(tool_store::ServerToolResults, tool::AbstractTool, result::String)
    if !haskey(tool_store.tool_results_history, tool)
        tool_store.tool_results_history[tool] = String[]
    end
    push!(tool_store.tool_results_history[tool], result)
end

"""
    get_tool_result(tool_store::ServerToolResults, tool::AbstractTool)

Get the latest result for a tool from history. Returns empty string if no results exist.
"""
function get_tool_result(tool_store::ServerToolResults, tool::AbstractTool)
    history = get(tool_store.tool_results_history, tool, String[])
    isempty(history) ? "" : last(history)
end
