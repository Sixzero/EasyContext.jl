using PromptingTools

export LLM_context_planner

struct ToolSuggestion
    suggested_tools::Vector{String}
end

function LLM_context_planner(ctx, tools; model::String="gpt3", kwargs...)
    tool_descriptions = join(["$name: $description" for (name, description, _) in tools], "\n")
    
    response = aiextract("""
    What tools do you think you're going to need to solve the query:
    <tools>
    $tool_descriptions
    </tools>
    <query>
    $ctx
    </query>
    Please list only the names of the tools you think are necessary.
    """;
    return_type = ToolSuggestion,
    model = model,
    kwargs...)
    
    return response.content.suggested_tools
end


