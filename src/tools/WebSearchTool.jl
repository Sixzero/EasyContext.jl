
@kwdef mutable struct WebSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    results::Vector{String} = []
end
create_tool(::Type{WebSearchTool}, tag::ToolTag) = WebSearchTool(query=strip(tag.args))
toolname(::Type{WebSearchTool}) = "web_search"
const WEBSEARCH_SCHEMA = (
    name = "web_search",
    description = "Search the web for information",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
get_tool_schema(::Type{WebSearchTool}) = WEBSEARCH_SCHEMA
get_description(cmd::Type{WebSearchTool}) = description_from_schema(WEBSEARCH_SCHEMA)

function execute(cmd::WebSearchTool; no_confirm=false)
    print_query(cmd.query)
    
    if no_confirm || get_user_confirmation()
        print_output_header()
        search_and_stream_results(cmd.query)
    else
        "\nSearch cancelled by user."
    end
end

function search_and_stream_results(query::String, output=IOBuffer())
    # Implement web search logic here using your preferred search API
    # Example using a hypothetical search_web function:
    # results = search_web(query)
    
    # for result in results
    #     println(result)
    #     write(output, result * "\n")
    # end
    
    # return format_search_output(output)
end

execute_required_tools(::WebSearchTool) = true
