using PromptingTools
using PromptingTools.Experimental.APITools: create_websearch

@kwdef mutable struct GoogleLoader <: AbstractLoader
    max_results::Int = 5
    include_answer::Bool = true
end

function (processor::GoogleLoader)(question::String)
    
    # Perform web search using Tavily API
    search_result = create_websearch(
        question;
        include_answer = processor.include_answer,
        max_results = processor.max_results
    )
    
    # Extract and format the search results
    web_summary = get(search_result.response, "answer", "")
    web_results = get(search_result.response, "results", [])
    
    formatted_results = """
    Web Search Summary: $(web_summary)
    
    Web Search Results:
    $(join(["$(i). $(get(result, "title", "")): $(get(result, "content", ""))" for (i, result) in enumerate(web_results)], "\n\n"))
    """
    @show formatted_results
    
    return formatted_results
end

function cut_history!(processor::GoogleLoader, keep::Int)
    # Reset the call counter when cutting history
end
