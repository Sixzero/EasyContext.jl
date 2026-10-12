using Test
using OpenRouter: AIMessage, to_openai_messages
using EasyContext: Session, push_message!, to_PT_messages, create_AI_message

# Thinking models (Qwen3.x on vLLM/DeepInfra) re-read their earlier reasoning in a
# tool loop; replaying a "." placeholder instead teaches them to stop thinking.
@testset "reasoning replay" begin
    tc = [Dict{String,Any}("id" => "c1", "type" => "function", "function" => Dict{String,Any}("name" => "f", "arguments" => "{}"))]
    s = Session()
    push!(s.messages, create_AI_message("calling"; tool_calls=tc, reasoning="plan: call f"))
    push!(s.messages, create_AI_message("plain"))
    out = to_openai_messages(to_PT_messages(s, "sys"))
    asst = filter(m -> m["role"] == "assistant", out)
    @test asst[1]["reasoning_content"] == "plan: call f"
    @test asst[2]["reasoning_content"] == "."   # no reasoning stored → placeholder unchanged

    @testset "merges keep both reasonings" begin
        s = Session()
        push_message!(s, AIMessage(content="a1", reasoning="r1"))
        push_message!(s, AIMessage(content="a2", reasoning="r2"))
        push_message!(s, AIMessage(content="a3"))
        @test length(s.messages) == 1
        @test s.messages[1].reasoning == "r1\nr2"
        push_message!(s, create_AI_message("a4"; reasoning="r4"))
        @test s.messages[1].reasoning == "r1\nr2\nr4"
    end
end
