export SubAgentStats, on_meta_ai

@kwdef mutable struct SubAgentStats
    cost::Float64 = 0.0
    elapsed::Float64 = 0.0
    input_tokens::Int = 0
    output_tokens::Int = 0
    cache_read_tokens::Int = 0
    cache_write_tokens::Int = 0
end

on_meta_ai(s::SubAgentStats) = (tokens, cost, elapsed) -> begin
    s.cost               += cost
    s.elapsed            += elapsed
    s.input_tokens       += tokens.prompt_tokens
    s.output_tokens      += tokens.completion_tokens
    s.cache_read_tokens  += tokens.input_cache_read
    s.cache_write_tokens += tokens.input_cache_write
end
