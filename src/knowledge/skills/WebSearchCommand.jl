

@kwdef mutable struct WebSearchCommand <: AbstractCommand
    id::UUID = uuid4()
    query::String
    results::Vector{String} = []
end
WebSearchCommand(cmd::CommandTag) = WebSearchCommand(query=strip(cmd.args))
commandname(cmd::Type{WebSearchCommand}) = WEB_SEARCH_TAG
get_description(cmd::Type{WebSearchCommand}) = """
Search the web for information. Provide a search query and get relevant results.
Format: Use "$(WEB_SEARCH_TAG)" followed by your search query or URL link. 
$(WEB_SEARCH_TAG) query $(STOP_SEQUENCE)
"""
stop_sequence(cmd::Type{WebSearchCommand}) = STOP_SEQUENCE


function execute(cmd::WebSearchCommand; no_confirm=false)
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
