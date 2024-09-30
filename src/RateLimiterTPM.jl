
using Dates
using Base.Threads

@enum TokenEstimationMethod begin
    CharCount
    CharCountDivTwo
    WordCount
    GPT2Approximation
end

@kwdef mutable struct RateLimiterTPM
    max_tokens::Int = 1_000_000
    time_window::Float64 = 60.0  # in seconds
    token_usage::Vector{Tuple{DateTime, Int}} = Tuple{DateTime, Int}[]
    lock::ReentrantLock = ReentrantLock()
    estimation_method::TokenEstimationMethod = CharCountDivTwo
end

function check_and_update!(limiter::RateLimiterTPM, input::Union{AbstractString, AbstractVector{<:AbstractString}})
    tokens = estimate_tokens(input, limiter.estimation_method)
    lock(limiter.lock) do
        now = Dates.now()
        # Remove entries older than the time window
        filter!(t -> (now - t[1]).value / 1000 < limiter.time_window, limiter.token_usage)
        
        # Calculate total tokens used in the current window
        total_tokens = sum(last, limiter.token_usage, init=0) + tokens
        
        if total_tokens > limiter.max_tokens
            return false
        end
        
        push!(limiter.token_usage, (now, tokens))
        return true
    end
end

function with_rate_limiter_tpm(f::Function, limiter::RateLimiterTPM)
    return function(input::Union{AbstractString, AbstractVector{<:AbstractString}}, args...; kwargs...)
        while true
            if check_and_update!(limiter, input)
                return f(input, args...; kwargs...)
            else
                sleep(1)  # Wait for 1 second before trying again
            end
        end
    end
end

# Helper function to estimate tokens based on input and method
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
        return sum(length(word) ÷ 4 + 1 for word in words)
    else
        error("Unknown token estimation method")
    end
end

# Overload estimate_tokens for vector input
function estimate_tokens(input::AbstractVector{<:AbstractString}, method::TokenEstimationMethod)
    return sum(estimate_tokens(str, method) for str in input)
end

# Function to change the estimation method
function set_estimation_method!(limiter::RateLimiterTPM, method::TokenEstimationMethod)
    limiter.estimation_method = method
end
