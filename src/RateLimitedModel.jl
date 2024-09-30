using HTTP
using JSON3
using Dates

"""
Rate limit handling based on the response headers.
# Usage
result = retry_on_rate_limit() do
    your_existing_function(arg1, arg2)
end
"""
function retry_on_rate_limit(f; max_retries=5, verbose=1, base_wait_time=1.0, msg="")
    retries = 0
    while retries < max_retries
        try
            return f()
        catch e
            if e isa HTTP.ExceptionRequest.StatusError
                status = e.status
                if status == 429  # Rate limit error
                    body = JSON3.read(String(e.response.body))
                    if get(body, :error, nothing) !== nothing && 
                       get(body.error, :code, nothing) == "rate_limit_exceeded"
                       idx = findfirst(v -> first(v) == "retry-after-ms", e.response.headers)
                       retry_after = if idx === nothing
                            @warn "There is no retry-after header. Retrying in 30 seconds."
                            30
                        else
                            Base.parse(Float64, last(e.response.headers[idx])) / 1000
                        end
                        @warn "Rate limit exceeded. Retrying in $retry_after seconds."
                        sleep(retry_after)
                    else
                        @warn "HTTP 429 error, but not a standard rate limit. Retrying in $base_wait_time seconds. ($e)"
                        sleep(base_wait_time)
                    end
                elseif 500 <= status < 600  # Server errors
                    wait_time = base_wait_time * (2^retries)  # Exponential backoff
                    @warn "Server error ($status). Retrying in $wait_time seconds."
                    sleep(wait_time)
                else
                    @error "Unhandled HTTP error: $(e)  "
                    rethrow(e)
                end
            else
                @error "Unhandled error type: $(typeof(e))"
                rethrow(e)
            end
            retries += 1
        end
    end
    error("Max retries reached")
end


