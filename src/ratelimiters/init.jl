include("RateLimiterRPM.jl")
include("RateLimiterHeader.jl")
include("RateLimiterTPM.jl")

# Create a global RateLimiterTPM instance
const ANTHROPIC_RATE_LIMITER = RateLimiterTPM(
    max_tokens = 400000,  # From anthropic-ratelimit-tokens-limit
    time_window = 60.0,   # Assuming the limit resets every minute
    estimation_method = CharCountDivTwo
)
const model2ratelimiter = Dict("claude" => ANTHROPIC_RATE_LIMITER, "claudeh" => ANTHROPIC_RATE_LIMITER,
)

# Add this new function after the includes
"""
    airate(args...; model::String = "claudeh", kwargs...)

A wrapper for `aigenerate` that automatically applies the appropriate rate limiter based on the model.

# Arguments
- `args...`: Arguments to be passed to `aigenerate`
- `model::String`: The model to use for generation. Defaults to "claudeh".
- `kwargs...`: Additional keyword arguments to be passed to `aigenerate`

# Returns
- The result of `aigenerate` after applying rate limiting
"""
function airate(args...; model::String = "claudeh", kwargs...)
    rate_limiter = get(model2ratelimiter, model, nothing)
    
    if isnothing(rate_limiter)
        # If no rate limiter is defined for the model, just call aigenerate directly
        return aigenerate(args...; model=model, kwargs...)
    else
        rate_limited_aigenerate = with_rate_limiter_tpm(aigenerate, rate_limiter)
        
        return retry_on_rate_limit(; max_retries=5, verbose=1) do
            response = rate_limited_aigenerate(args...; model=model, kwargs...)
            # Update rate limiter with actual token usage
            update_rate_limiter!(rate_limiter, response)
            return response
        end
    end
end

# Update the rate limiter based on the actual token usage
function update_rate_limiter!(rate_limiter::RateLimiterTPM, response::PromptingTools.AIMessage)
    actual_tokens = if response.tokens isa Tuple && length(response.tokens) >= 2
        response.tokens[1] + response.tokens[2]  # input_tokens + output_tokens
    elseif response.tokens isa Dict && haskey(response.tokens, 1) && haskey(response.tokens, 2)
        response.tokens[1] + response.tokens[2]  # input_tokens + output_tokens
    else
        return  # If we can't determine the token count, exit the function early
    end

    lock(rate_limiter.lock) do
        # Remove the estimated token count
        if !isempty(rate_limiter.token_usage)
            pop!(rate_limiter.token_usage)
        end
        # Add the actual token count
        push!(rate_limiter.token_usage, (Dates.now(), actual_tokens))
    end

    if haskey(response.extras, :response) && response.extras[:response] isa HTTP.Response
        headers = Dict(response.extras[:response].headers)
        if haskey(headers, "anthropic-ratelimit-tokens-limit")
            new_limit = parse(Int, headers["anthropic-ratelimit-tokens-limit"])
            rate_limiter.max_tokens = new_limit
        end
        if haskey(headers, "anthropic-ratelimit-tokens-reset")
            reset_time = DateTime(headers["anthropic-ratelimit-tokens-reset"], "yyyy-mm-ddTHH:MM:SSZ")
            new_window = (reset_time - now(UTC)).value / 1000.0  # Convert to seconds
            rate_limiter.time_window = new_window
        end
    end
end

export airate
