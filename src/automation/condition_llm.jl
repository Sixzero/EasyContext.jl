using PromptingTools

"""
    condition_llm(condition::AbstractString; model::AbstractString="gpt4om", verbose::Bool=false)

Evaluates a given condition using an AI model and returns a boolean result.

# Arguments
- `condition::AbstractString`: The condition to be evaluated.
- `model::AbstractString="gpt4om"`: The AI model to use for evaluation.
- `verbose::Bool=false`: Whether to print additional information.

# Returns
- `Bool`: The result of the condition evaluation.

# Example
```julia
if condition_llm("Is it raining today?")
    println("Bring an umbrella!")
else
    println("Enjoy the sunshine!")
end
```
"""
function condition_llm(condition::AbstractString; model::AbstractString="gpt4om", verbose::Bool=false)
    result = aiclassify(condition; model=model, verbose=verbose)
    return parse(Bool, result)
end


export condition_llm
