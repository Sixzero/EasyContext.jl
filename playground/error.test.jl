using JLD2
using HTTP
using JSON3

e = load("error_0.jld2", "error")
@show e
if e isa HTTP.ExceptionRequest.StatusError && e.status == 429
  body = JSON3.read(String(e.response.body))
  if get(body, :error, nothing) !== nothing && 
     get(body.error, :code, nothing) == "rate_limit_exceeded"
     @show (e.response.headers)
     idx = findfirst(v -> first(v) == "retry-after-ms", e.response.headers)
     idx = nothing
     retry_after = if idx === nothing
      @warn "There is no retry-after header. Retrying in 30 seconds."
      30
     else
      parse(Float64, last(e.response.headers[idx])) / 1000
     end
      verbose > 0 && @warn "Rate limit exceeded. Retrying in $retry_after seconds."
      sleep(retry_after)
  else
      rethrow(e)
  end
else
  rethrow(e)
end

#%%
using Test
using ProgressMeter


# Mock embedding function
function mock_embed(chunk)
  sleep(0.1)  # Simulate processing time
  return rand(10, length(chunk))  # Return dummy embeddings
end

# Function to test
function process_with_progress(data, batch_size)
  n_batches = length(collect(Iterators.partition(data, batch_size)))
  
  p = Progress(n_batches; desc="Processing: ", showspeed=true)
  
  results = asyncmap(Iterators.partition(data, batch_size);
      ntasks=Threads.nthreads()) do chunk
      result = mock_embed(chunk)
      next!(p)
      result
  end
  
  finish!(p)
  return results
end

@testset "Async Progress Bar Tests" begin
  data = 1:100
  batch_size = 10

  @testset "Basic Functionality" begin
      results = process_with_progress(data, batch_size)
      @test length(results) == 10  # Number of batches
      @test all((size(results,1), size(results[1],1)) .== (10, batch_size))
  end

  # @testset "Different Batch Sizes" begin
  #     for bs in [5, 20, 50]
  #         results = process_with_progress(data, bs)
  #         expected_batches = ceil(Int, length(data) / bs)
  #         @test length(results) == expected_batches
  #         @test all(size.(results[1:end-1]) .== (10, bs))
  #         @test size(results[end], 2) <= bs  # Last batch might be smaller
  #     end
  # end
end

#%%
using PromptingTools

ai"Are you here?"gemini_f
#%%
using GoogleGenAI
models = list_models(ENV["GOOGLE_API_KEY"])
for m in models
    if "generateContent" in m[:supported_generation_methods]
        println(m[:display_name])
    end
end