

export TokenEstimationMethod, estimate_tokens


@enum TokenEstimationMethod begin
    CharCount
    CharCountDivTwo
    WordCount
    GPT2Approximation
end

function estimate_tokens(input::AbstractString, method::TokenEstimationMethod)
    if method == CharCount
        return length(input)
    elseif method == CharCountDivTwo
        return div(length(input), 2)
    elseif method == WordCount
        return length(split(input))
    elseif method == GPT2Approximation
        # This is a rough approximation of GPT-2 tokenization
        # It's not exact, but it's closer than character count for English text
        words = split(input)
        return length(words)>0 ? sum(length(word) ÷ 4 + 1 for word in words) : 1
    else
        error("Unknown token estimation method")
    end
end

# Overload estimate_tokens for vector input
function estimate_tokens(input::AbstractVector{<:AbstractString}, method::TokenEstimationMethod)
    return sum(estimate_tokens(str, method) for str in input)
end

