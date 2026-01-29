"Search the web for information"
@deftool :confirm :auto_execute web_search(query::String) = begin
    print_query(query)
    search_and_stream_results(query)
end

function search_and_stream_results(query::String)
    # Implement web search logic here
    "Search results for: $query"
end
