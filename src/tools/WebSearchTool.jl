using ToolCallFormat: ParsedCall, AbstractTool
using ToolCallFormat: toolname, get_tool_schema, get_description, description_from_schema
using ToolCallFormat: execute, execute_required_tools, create_tool

@kwdef mutable struct WebSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    results::Vector{String} = []
end

function ToolCallFormat.create_tool(::Type{WebSearchTool}, call::ParsedCall)
    query = get(call.kwargs, "query", nothing)
    WebSearchTool(query=query !== nothing ? strip(query.value) : "")
end

ToolCallFormat.toolname(::Type{WebSearchTool}) = "web_search"

const WEBSEARCH_SCHEMA = (
    name = "web_search",
    description = "Search the web for information",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)

ToolCallFormat.get_tool_schema(::Type{WebSearchTool}) = WEBSEARCH_SCHEMA
ToolCallFormat.get_description(::Type{WebSearchTool}) = description_from_schema(WEBSEARCH_SCHEMA)

function ToolCallFormat.execute(cmd::WebSearchTool; no_confirm=false, kwargs...)
    print_query(cmd.query)

    if no_confirm || get_user_confirmation()
        print_output_header()
        search_and_stream_results(cmd.query)
    else
        "\nSearch cancelled by user."
    end
end

function search_and_stream_results(query::String, output=IOBuffer())
    # Implement web search logic here
end

ToolCallFormat.execute_required_tools(::WebSearchTool) = true
