
export selector_llm

struct ToolSuggestion
    suggested_tools::Vector{String}
end

function selector_llm(ctx, tools; model::String="gpt3", kwargs...)
    tool_descriptions = join(["$name: $description" for (name, description, _) in tools], "\n")
    
    response = aiextract("""
    What tools do you think you're going to need to solve the query:
    <tools>
    $tool_descriptions
    </tools>
    Please list only the names of the tools you think are necessary.
    <query>
    $ctx
    </query>
    """;
    return_type = ToolSuggestion,
    model = model,
    kwargs...)
    
    return response.content.suggested_tools
end


